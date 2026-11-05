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
        let before = board
        let host = NSHostingView(rootView: ProductionImagePlanningSheet(shot: shot, board: board, dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 620)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(board == before)
    }
}
