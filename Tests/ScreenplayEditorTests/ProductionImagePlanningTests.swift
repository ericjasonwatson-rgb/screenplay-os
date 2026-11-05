import Foundation
import Testing
import ScreenplayDomain

@Suite("Approved-board production image planning")
struct ProductionImagePlanningTests {
    private func fixture() -> (Shot, BoardFrame) {
        let shot = Shot(sceneSpineID: "S001", shotNumber: 1, label: "1A — Beach wide",
                        setup: .establishing, notes: "Low horizon")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Beach composition",
                               durationSeconds: 3.5, status: .boarded,
                               notes: "Mew on left third")
        let image = BoardImageVersion(
            fileURL: URL(fileURLWithPath: "/tmp/board.png"),
            sha256: String(repeating: "a", count: 64),
            prompt: "rough board", model: "test")
        board.imageVersions = [image]
        board.selectedImageID = image.id
        return (shot, board)
    }

    @Test func approvedBoardCreatesAStablePromptWithoutChangingTheBoard() throws {
        let (shot, board) = fixture()
        let before = board
        let brief = try ProductionImagePlanning.prepare(
            shot: shot, board: board, approvedBoardIDs: [board.id],
            directingInstruction: "Use golden-hour light",
            styleInstruction: "Naturalistic animation",
            referencePaths: ["references/character.png"])
        #expect(brief.shotID == shot.id)
        #expect(brief.boardID == board.id)
        #expect(brief.selectedBoardImageID == board.selectedImageID)
        #expect(brief.promptPreview.contains("golden-hour"))
        #expect(brief.promptPreview.contains("Mew on left third"))
        #expect(brief.promptSHA256.count == 64)
        #expect(board == before)
        try ProductionImagePlanning.validateCurrent(
            brief, shot: shot, board: board, approvedBoardIDs: [board.id])
    }

    @Test func cannotPromoteWithoutExplicitBoardApproval() throws {
        let (shot, board) = fixture()
        #expect(throws: ProductionImagePlanningError.boardNotApproved) {
            try ProductionImagePlanning.prepare(shot: shot, board: board,
                approvedBoardIDs: [], directingInstruction: "Keep the framing")
        }
    }

    @Test func cannotPromoteUnselectedOrMismatchedBoard() throws {
        let (shot, board) = fixture()
        var noSelection = board
        noSelection.selectedImageID = nil
        #expect(throws: ProductionImagePlanningError.missingSelectedImage) {
            try ProductionImagePlanning.prepare(shot: shot, board: noSelection,
                approvedBoardIDs: [board.id], directingInstruction: "Keep the framing")
        }
        let wrongShot = Shot(sceneSpineID: "S001", label: "Other shot")
        #expect(throws: ProductionImagePlanningError.wrongShot) {
            try ProductionImagePlanning.prepare(shot: wrongShot, board: board,
                approvedBoardIDs: [board.id], directingInstruction: "Keep the framing")
        }
    }

    @Test func snapshotRefusesChangedBoardAndRevokedApproval() throws {
        let (shot, board) = fixture()
        let brief = try ProductionImagePlanning.prepare(
            shot: shot, board: board, approvedBoardIDs: [board.id],
            directingInstruction: "Keep the framing")
        var changed = board
        changed.notes = "Different blocking"
        #expect(throws: ProductionImagePlanningError.staleBoard) {
            try ProductionImagePlanning.validateCurrent(
                brief, shot: shot, board: changed, approvedBoardIDs: [board.id])
        }
        #expect(throws: ProductionImagePlanningError.staleBoard) {
            try ProductionImagePlanning.validateCurrent(
                brief, shot: shot, board: board, approvedBoardIDs: [])
        }
    }

    @Test func referencePathTraversalIsRejected() throws {
        let (shot, board) = fixture()
        for path in ["../hidden.png", "/private/secret.png", "file:///secret.png",
                     "references/../../hidden.png", "C:/secret.png", "assets\\secret.png"] {
            #expect(throws: ProductionImagePlanningError.unsafeReference) {
                try ProductionImagePlanning.prepare(
                    shot: shot, board: board, approvedBoardIDs: [board.id],
                    directingInstruction: "Keep framing", referencePaths: [path])
            }
        }
    }
}
