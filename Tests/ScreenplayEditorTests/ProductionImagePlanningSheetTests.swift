import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production image planning presentation")
@MainActor
struct ProductionImagePlanningSheetTests {
    @Test func localOnlyPlanningSheetCanRenderWithoutGenerating() throws {
        let shot = Shot(sceneSpineID: "S001", label: "Test wide shot")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Test board", durationSeconds: 3)
        let selected = BoardImageVersion(fileURL: URL(fileURLWithPath: "/tmp/test.png"),
                                         sha256: String(repeating: "a", count: 64),
                                         prompt: "board", model: "fixture")
        board.imageVersions = [selected]
        board.selectedImageID = selected.id
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ProductionPlanningUI.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: root, preferences: preferences)
        model.newDocument()
        // Exercise the absent-board state without bypassing the private document setter.
        // Populated-board approval and identity are covered by domain-level tests.
        let before = model.document
        let host = NSHostingView(rootView: ProductionImagePlanningSheet(
            model: model, boardID: board.id, dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 620)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(model.document == before)
    }
}
