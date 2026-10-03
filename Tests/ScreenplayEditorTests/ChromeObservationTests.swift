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
            let failure = chrome.snapshot
            #expect(model.saveSeparateCopy(to: url.deletingLastPathComponent().appendingPathComponent("copy.json")))
            await settle()
            #expect(model.saveProblem == nil && !model.hasUnsavedChanges)
            #expect(chrome.snapshot != failure)
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
