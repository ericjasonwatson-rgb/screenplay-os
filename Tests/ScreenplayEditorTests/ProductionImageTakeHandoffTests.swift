import CryptoKit
import Foundation
import Testing
import ScreenplayDomain

@Suite("Storyboard to production-image take handoff")
struct ProductionImageTakeHandoffTests {
    private func fixture() -> (Shot, BoardFrame, ProductionImageBrief) {
        let shot = Shot(sceneSpineID: "S001", shotNumber: 1,
                        label: "Mew on beach", setup: .establishing,
                        notes: "Wide locked camera")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Beach board",
                               durationSeconds: 3.5, status: .boarded,
                               notes: "Left third composition")
        let selected = BoardImageVersion(
            fileURL: URL(fileURLWithPath: "/tmp/reference-board.png"),
            sha256: String(repeating: "a", count: 64),
            prompt: "Storyboard", model: "fixture")
        board.imageVersions = [selected]
        board.selectedImageID = selected.id
        let brief = try! ProductionImagePlanning.prepare(
            shot: shot, board: board, approvedBoardIDs: [board.id],
            directingInstruction: "Golden hour; retain composition",
            referencePaths: ["references/mew.png"])
        return (shot, board, brief)
    }

    // Signature fixture is NOT a valid decoded PNG. The real adapter must
    // validate image decoding before calling candidate().
    private let mockOutput = Data([137,80,78,71,13,10,26,10,0,1,2,3])

    @Test func outputIsACandidateAndNeverReplacesApprovedBoard() throws {
        let (shot, board, brief) = fixture()
        let original = board
        let id = UUID(), job = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
        let take = try ProductionImageTakeHandoff.candidate(
            brief: brief, currentShot: shot, currentBoard: board,
            approvedBoardIDs: [board.id],
            output: mockOutput, storedMediaURL: URL(fileURLWithPath: "/tmp/production.png"),
            takeID: id, jobID: job, providerID: "mock", modelID: "fixture", generatedAt: date)
        #expect(take.id == id && take.kind == .generatedImage && take.status == .candidate)
        #expect(take.shotID == shot.id && take.boardFrameID == board.id)
        #expect(take.durationSeconds == board.durationSeconds)
        #expect(take.provenance.generationJobID == job)
        #expect(take.provenance.prompt == brief.promptPreview)
        #expect(take.provenance.promptSHA256 == brief.promptSHA256)
        #expect(take.provenance.referenceAssetPaths == ["references/mew.png"])
        #expect(take.sha256 == SHA256.hash(data: mockOutput).map { String(format: "%02x", $0) }.joined())
        #expect(board == original)
        #expect(board.selectedImageID == original.selectedImageID)
        #expect(take.order == board.imageVersions.count)
    }

    @Test func changedBoardOrRevokedApprovalCannotCreateTake() throws {
        let (shot, board, brief) = fixture()
        var edited = board
        edited.notes = "Different composition"
        #expect(throws: ProductionImagePlanningError.staleBoard) {
            try ProductionImageTakeHandoff.candidate(
                brief: brief, currentShot: shot, currentBoard: edited,
                approvedBoardIDs: [board.id], output: mockOutput,
                storedMediaURL: URL(fileURLWithPath: "/tmp/take.png"),
                takeID: UUID(), jobID: UUID(), providerID: "mock",
                modelID: "fixture", generatedAt: Date())
        }
        #expect(throws: ProductionImagePlanningError.staleBoard) {
            try ProductionImageTakeHandoff.candidate(
                brief: brief, currentShot: shot, currentBoard: board,
                approvedBoardIDs: [], output: mockOutput,
                storedMediaURL: URL(fileURLWithPath: "/tmp/take.png"),
                takeID: UUID(), jobID: UUID(), providerID: "mock",
                modelID: "fixture", generatedAt: Date())
        }
    }

    @Test func refusesAbsentOutputAndInvalidProvider() throws {
        let (shot, board, brief) = fixture()
        #expect(throws: ProductionImageTakeHandoff.Failure.missingOutput) {
            try ProductionImageTakeHandoff.candidate(
                brief: brief, currentShot: shot, currentBoard: board,
                approvedBoardIDs: [board.id], output: Data(),
                storedMediaURL: URL(fileURLWithPath: "/tmp/take.png"),
                takeID: UUID(), jobID: UUID(), providerID: "mock",
                modelID: "fixture", generatedAt: Date())
        }
        #expect(throws: ProductionImageTakeHandoff.Failure.invalidProvenance) {
            try ProductionImageTakeHandoff.candidate(
                brief: brief, currentShot: shot, currentBoard: board,
                approvedBoardIDs: [board.id], output: mockOutput,
                storedMediaURL: URL(fileURLWithPath: "/tmp/take.png"),
                takeID: UUID(), jobID: UUID(), providerID: "",
                modelID: "fixture", generatedAt: Date())
        }
    }
}
