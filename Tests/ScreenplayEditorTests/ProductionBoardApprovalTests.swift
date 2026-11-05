import Foundation
import Testing
import ScreenplayDomain

@Suite("Revision-bound storyboard approvals")
struct ProductionBoardApprovalTests {
    private func fixture() -> (Shot, BoardFrame) {
        let shot = Shot(sceneSpineID: "S001", label: "Wide", notes: "Do not move the camera")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Opening", durationSeconds: 3.5,
                               status: .boarded, notes: "Mew in the foreground")
        let image = BoardImageVersion(fileURL: URL(fileURLWithPath: "/tmp/board.png"),
            sha256: String(repeating: "a", count: 64), prompt: "sketch", model: "fixture")
        board.imageVersions = [image]
        board.selectedImageID = image.id
        return (shot, board)
    }

    @Test func exactApprovalRoundTripsThroughLocalSidecar() throws {
        let (shot, board) = fixture()
        let projectID = UUID()
        let original = try ProductionBoardApprovals.approve(
            projectID: projectID, shot: shot, board: board,
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("approvals/board.json")
        try ProductionBoardApprovals.store(original, at: file)
        let loaded = try ProductionBoardApprovals.load(at: file)
        #expect(loaded == original)
        try ProductionBoardApprovals.validate(loaded, projectID: projectID, shot: shot, board: board)
    }

    @Test func editedShotAndBoardInvalidateEarlierApproval() throws {
        let (shot, board) = fixture()
        let project = UUID()
        let approval = try ProductionBoardApprovals.approve(projectID: project, shot: shot, board: board)
        var changedBoard = board
        changedBoard.notes = "Change composition"
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.validate(approval, projectID: project, shot: shot, board: changedBoard)
        }
        var changedShot = shot
        changedShot.notes = "Camera now moves"
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.validate(approval, projectID: project, shot: changedShot, board: board)
        }
        var changedSelection = board
        changedSelection.selectedImageID = nil
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.validate(approval, projectID: project, shot: shot, board: changedSelection)
        }
    }

    @Test func approvalNeverTransfersToAnotherProject() throws {
        let (shot, board) = fixture()
        let approval = try ProductionBoardApprovals.approve(projectID: UUID(), shot: shot, board: board)
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.validate(approval, projectID: UUID(), shot: shot, board: board)
        }
    }

    @Test func refusesSymbolicLinkApprovalFile() throws {
        let (shot, board) = fixture()
        let approval = try ProductionBoardApprovals.approve(projectID: UUID(), shot: shot, board: board)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let real = root.appendingPathComponent("real.json")
        try ProductionBoardApprovals.store(approval, at: real)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.load(at: link)
        }
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionBoardApprovals.store(approval, at: link)
        }
    }
}
