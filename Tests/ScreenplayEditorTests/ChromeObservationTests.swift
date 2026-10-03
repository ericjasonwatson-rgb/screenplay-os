import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Writing chrome observation", .serialized) @MainActor
struct ChromeObservationTests {
    private func withModel(_ body: @MainActor (ScreenplayViewModel) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ChromeObservation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: defaults)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
            with: "INT. ROOM - DAY\nAn action.\nAnother action.")
        model.navigationVisible = false
        model.contextAssistantVisible = false
        model.rememberDocumentCaret(NSRange(location: (model.writingText as NSString).length, length: 0))
        await settle()
        try await body(model)
        await settle()
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    @Test func ordinaryTypingSkipsChromeRefreshButStillSavesAndUndoes() async throws {
        try await withModel { model in
            let chrome = model.chromeState
            let before = chrome.snapshot
            let original = model.writingText
            model.replaceWritingText(in: NSRange(location: (original as NSString).length, length: 0), with: " More.")
            await settle()
            #expect(chrome.snapshot == before)
            #expect(model.writingText == original + " More.")
            let saved = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self,
                from: Data(contentsOf: #require(model.saveURL)))
            #expect(saved.screenplay.elements == model.elements)
            model.undo()
            await settle()
            #expect(model.writingText == original)
            #expect(chrome.snapshot != before) // Redo becomes available.
        }
    }

    @Test func visibleControlsAndErrorsRefreshEvenWhenTextDoesNot() async throws {
        try await withModel { model in
            let chrome = model.chromeState
            @MainActor func expectRefresh(_ change: @MainActor () -> Void) async {
                let before = chrome.snapshot
                change()
                await settle()
                #expect(chrome.snapshot != before)
            }
            await expectRefresh { model.pageZoom = 1.2 }
            await expectRefresh { model.darkPageMode.toggle() }
            await expectRefresh { model.toggleWritingEmphasis(\.bold) }
            await expectRefresh { model.changeWritingTypography(size: 14) }
            await expectRefresh { model.setRevisionMode(true) }
            await expectRefresh { model.sourceNavigationProblem = "" }
            await expectRefresh { model.sourceNavigationProblem = nil }
            await expectRefresh { model.errorMessage = "" }
            await expectRefresh { model.errorMessage = nil }
            await expectRefresh { model.setSelectedElementType(.dialogue) }
            await expectRefresh {
                model.replaceWritingText(in: NSRange(location: 0, length: 0), with: "EXT. FIELD - NIGHT\n")
            }
        }
    }

    @Test func externalSaveConflictAndRecoveryRefreshStatus() async throws {
        try await withModel { model in
            let chrome = model.chromeState
            let before = chrome.snapshot
            let shell = chrome.signal(for: .shell, model: model)
            let identity = chrome.signal(for: .identity, model: model)
            let originalShell = shell.value, originalIdentity = identity.value
            let url = try #require(model.saveURL)
            var outside = try #require(model.document)
            outside.screenplay.elements[1].text = "External change."
            let data = try JSONEncoder.openScreenplayEncoder().encode(outside)
            try data.write(to: url, options: .atomic)
            model.replaceWritingText(in: NSRange(location: (model.writingText as NSString).length, length: 0), with: " Local.")
            await settle()
            #expect(model.saveProblem != nil && model.hasUnsavedChanges)
            #expect(chrome.snapshot != before)
            #expect(try Data(contentsOf: url) == data)
            #expect(shell.value != originalShell && identity.value != originalIdentity)
            let failedShell = shell.value, failedIdentity = identity.value
            let failure = chrome.snapshot
            #expect(model.saveSeparateCopy(to: url.deletingLastPathComponent().appendingPathComponent("copy.json")))
            await settle()
            #expect(model.saveProblem == nil && !model.hasUnsavedChanges)
            #expect(chrome.snapshot != failure)
            #expect(shell.value != failedShell && identity.value != failedIdentity)
        }
    }

    @Test func panelsAndOtherModesRetainFullObservation() async throws {
        try await withModel { model in
            let chrome = model.chromeState
            @MainActor func expectFull() async {
                await settle()
                guard case .full = chrome.snapshot else {
                    Issue.record("An open panel or another mode must retain full observation")
                    return
                }
                let before = chrome.snapshot
                model.objectWillChange.send()
                await settle()
                #expect(chrome.snapshot != before)
            }
            model.navigationVisible = true
            await expectFull()
            model.navigationVisible = false
            model.contextAssistantVisible = true
            await expectFull()
            model.contextAssistantVisible = false
            model.titlePagePresented = true
            await expectFull()
            model.titlePagePresented = false
            model.commandPaletteVisible = true
            await expectFull()
            model.commandPaletteVisible = false
            model.setWorkflowMode(.outline)
            await expectFull()
            model.setWorkflowMode(.writing)
            await settle()
            guard case .writing = chrome.snapshot else {
                Issue.record("Returning to writing should resume selective observation")
                return
            }
        }
    }

    @Test func firstUndoAvailabilityDoesNotInvalidateTheWritingShell() async throws {
        try await withModel { model in
            model.newDocument()
            model.rememberDocumentCaret(NSRange(location: (model.writingText as NSString).length, length: 0))
            await settle()
            #expect(!model.canUndo)
            let chrome = model.chromeState
            let shell = chrome.signal(for: .shell, model: model)
            let workspace = chrome.signal(for: .workspace, model: model)
            let commands = chrome.signal(for: .commands, model: model)
            let beforeShell = shell.value, beforeWorkspace = workspace.value, beforeCommands = commands.value
            model.replaceWritingText(in: NSRange(location: (model.writingText as NSString).length, length: 0), with: "First edit.")
            await settle()
            #expect(model.canUndo)
            #expect(commands.value != beforeCommands)
            #expect(shell.value == beforeShell && workspace.value == beforeWorkspace)
            let afterTyping = commands.value
            model.undo()
            await settle()
            #expect(!model.canUndo)
            #expect(commands.value != afterTyping)
        }
    }

    @Test func scopedControlsStayCurrentWithBothPanelsOpen() async throws {
        try await withModel { model in
            model.navigationVisible = true
            model.contextAssistantVisible = true
            await settle()
            let chrome = model.chromeState
            @MainActor func expectRefresh(_ region: ScreenplayChromeState.Region, _ change: @MainActor () -> Void) async {
                let signal = chrome.signal(for: region, model: model)
                let before = signal.value
                change()
                await settle()
                #expect(signal.value != before)
            }
            await expectRefresh(.navigation) { model.pageZoom = 1.2 }
            await expectRefresh(.status) { model.darkPageMode.toggle() }
            await expectRefresh(.page) { model.toggleWritingEmphasis(\.bold) }
            await expectRefresh(.page) { model.changeWritingTypography(size: 14) }
            await expectRefresh(.commands) { model.setRevisionMode(true) }
            await expectRefresh(.elementType) { model.setSelectedElementType(.dialogue) }
            await expectRefresh(.shell) { model.sourceNavigationProblem = "Source missing" }
            await expectRefresh(.shell) { model.sourceNavigationProblem = nil }
            await expectRefresh(.page) { model.errorMessage = "Format notice" }
            await expectRefresh(.workspace) { model.contextAssistantVisible = false }
            await expectRefresh(.shell) { model.navigationVisible = false }
            await expectRefresh(.pages) {
                model.replaceWritingText(in: NSRange(location: (model.writingText as NSString).length, length: 0),
                    with: String(repeating: "\nAn additional action paragraph.", count: 100))
            }
            let pages = model.printedLayout
            #expect(chrome.signal(for: .pages, model: model).value == .pages(pages.pages.map(\.label),
                pages.pages.indices.map { pages.firstSourceCaret(onPage: $0) != nil }))
        }
    }

    @Test func windowChangesModesAndReturnsToCurrentText() async throws {
        try await withModel { model in
            let host = NSHostingView(rootView: ContentView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            @MainActor func editor(in view: NSView) -> WritingTextView? {
                if let text = view as? WritingTextView { return text }
                return view.subviews.lazy.compactMap { editor(in: $0) }.first
            }
            @MainActor func refresh() async {
                await settle()
                host.layoutSubtreeIfNeeded()
            }
            await refresh()
            let text = try #require(editor(in: host))
            text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
            text.insertText(" A native edit.", replacementRange: text.selectedRange())
            await refresh()
            #expect(text.string == model.writingText)
            model.navigationVisible = true
            model.contextAssistantVisible = true
            await refresh()
            #expect(try #require(editor(in: host)) === text)
            text.insertText(" With panels open.", replacementRange: text.selectedRange())
            await refresh()
            #expect(text.string == model.writingText)
            model.undo()
            await refresh()
            #expect(text.string == model.writingText)
            let expected = model.writingText
            model.setWorkflowMode(.outline)
            await refresh()
            #expect(editor(in: host) == nil)
            model.setWorkflowMode(.writing)
            await refresh()
            #expect(try #require(editor(in: host)).string == expected)
        }
    }
}
