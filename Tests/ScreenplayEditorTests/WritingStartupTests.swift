import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Writing-first startup")
@MainActor
struct WritingStartupTests {
    private func withEnvironment(_ body: (URL, UserDefaults) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "WritingStartupTests.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        try body(folder, prefs)
    }

    @Test func firstLaunchStartsBlankWithoutDemoOrProductionPanes() throws {
        try withEnvironment { folder, prefs in
            let model = ScreenplayViewModel(autosaveDirectory: folder, preferences: prefs)
            #expect(model.title == "Untitled Screenplay")
            #expect(model.elements.allSatisfy { $0.text.isEmpty })
            #expect(model.sourceURL == nil && model.saveURL == nil)
            #expect(model.workflowMode == .writing)
            #expect(!model.darkPageMode)
            #expect(!model.navigationVisible && !model.contextAssistantVisible)
        }
    }

    @Test func restartReopensLastAvailableRecentProjectWithoutChangingItsBytes() throws {
        try withEnvironment { folder, prefs in
            let writer = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
            writer.newDocument()
            writer.replaceWritingText(in: NSRange(location: 0, length: (writer.writingText as NSString).length),
                                      with: "INT. ROOM - DAY\nA writer begins.\nMARA\nHello.")
            writer.save()
            let url = try #require(writer.saveURL)
            let data = try Data(contentsOf: url)
            // A missing recent item must not block a surviving project outside Downloads.
            prefs.set([folder.appendingPathComponent("missing.json").path, url.path], forKey: "ScreenplayOSRecentDocuments")
            let reopened = ScreenplayViewModel(autosaveDirectory: folder, preferences: prefs)
            #expect(reopened.saveURL == url)
            #expect(reopened.document == (try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)))
            #expect(try Data(contentsOf: url) == data)
        }
    }

    @Test func unreadableRecentProjectIsPreservedAndFailureExplained() throws {
        try withEnvironment { folder, prefs in
            let url = folder.appendingPathComponent("damaged.json")
            let bytes = Data("not a screenplay".utf8)
            try bytes.write(to: url)
            prefs.set([url.path], forKey: "ScreenplayOSRecentDocuments")
            let model = ScreenplayViewModel(autosaveDirectory: folder, preferences: prefs)
            #expect(model.document != nil && model.saveURL == nil)
            #expect(model.elements.allSatisfy { $0.text.isEmpty })
            #expect(model.errorMessage?.contains("Could not reopen") == true)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func newFromProductionReturnsToWritingAndPreservesPreviousWork() throws {
        try withEnvironment { folder, prefs in
            let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nKeep this scene.")
            let url = try #require(model.saveURL)
            let bytes = try Data(contentsOf: url)
            model.setWorkflowMode(.edit)
            model.contextAssistantVisible = true
            model.navigationVisible = true
            model.focusMode = true
            model.commandPaletteVisible = true
            model.newDocument()
            #expect(model.workflowMode == .writing && model.sidebarMode == .navigator)
            #expect(!model.navigationVisible && !model.contextAssistantVisible && !model.focusMode)
            #expect(!model.commandPaletteVisible)
            #expect(model.selectedElement?.type == .sceneHeading)
            #expect(model.elements.allSatisfy { $0.text.isEmpty })
            #expect(try Data(contentsOf: url) == bytes)
        }
    }
}
