import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Siri workspace navigation")
@MainActor
struct SiriWorkspaceIntentsTests {
    @Test func mapsTheFiveViewsToExistingWorkflowModes() {
        #expect(SiriWorkspaceChoice.outline.workflowMode == .outline)
        #expect(SiriWorkspaceChoice.script.workflowMode == .writing)
        #expect(SiriWorkspaceChoice.shot.workflowMode == .directing)
        #expect(SiriWorkspaceChoice.boards.workflowMode == .boards)
        #expect(SiriWorkspaceChoice.edit.workflowMode == .edit)
    }

    @Test func consumesAReadOnlyNavigationRequestExactlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SiriWorkspaceTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false,
                                        autosaveDirectory: root, preferences: preferences)
        model.newDocument()
        let before = model.document
        SiriWorkspaceNavigation.request(.boards, preferences: preferences)
        #expect(SiriWorkspaceNavigation.consume(model: model, preferences: preferences))
        #expect(model.workflowMode == .boards)
        #expect(model.document == before)
        #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences))
    }

    @Test func malformedRequestIsClearedWithoutNavigation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SiriWorkspaceTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false,
                                        autosaveDirectory: root, preferences: preferences)
        model.newDocument()
        preferences.set("erase-film", forKey: "ScreenplayOS.PendingSiriWorkspace")
        #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences))
        #expect(model.workflowMode == .writing)
        #expect(preferences.string(forKey: "ScreenplayOS.PendingSiriWorkspace") == nil)
    }
}
