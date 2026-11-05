import Foundation
import Testing
import ScreenplayDomain

@Suite("Production image consent staging")
struct ProductionImageJobPlanningTests {
    private func fixture() throws -> (Shot, BoardFrame, ProductionImageBrief) {
        let shot = Shot(sceneSpineID: "S001", shotNumber: 1, label: "Beach wide")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S001",
                               frameNumber: 1, label: "Approved beach board",
                               durationSeconds: 3, status: .boarded)
        let image = BoardImageVersion(
            fileURL: URL(fileURLWithPath: "/tmp/board.png"),
            sha256: String(repeating: "a", count: 64),
            prompt: "board sketch", model: "fixture")
        board.imageVersions = [image]
        board.selectedImageID = image.id
        let brief = try ProductionImagePlanning.prepare(
            shot: shot, board: board, approvedBoardIDs: [board.id],
            directingInstruction: "Preserve composition")
        return (shot, board, brief)
    }

    @Test func stagesUnsentJobWithExactBoardIdentityAndReference() throws {
        let (shot, board, brief) = try fixture()
        let project = UUID(), jobID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try ProductionImageJobPlanning.awaitingConsent(
            brief: brief, shot: shot, board: board, approvedBoardIDs: [board.id],
            projectID: project, jobID: jobID, providerID: "mock",
            modelID: "fixture", boardRelativePath: "Board Images/board.png",
            createdAt: date)
        #expect(record.id == jobID)
        #expect(record.projectID == project)
        #expect(record.status == .awaitingConsent)
        #expect(record.consentedAt == nil && record.submittedAt == nil)
        #expect(record.request.references.count == 1)
        #expect(record.request.references[0].id == brief.selectedBoardImageID)
        #expect(record.request.references[0].sha256 == brief.selectedBoardImageSHA256)
        #expect(record.request.prompt == brief.promptPreview)
        #expect(record.target.id == brief.boardID)
        #expect(record.requestSHA256 == (try record.request.sha256()))
        #expect(board.selectedImageID == brief.selectedBoardImageID)
        _ = try GenerationJobLedger(projectID: project, jobs: [record]).validated()
    }

    @Test func refusesUnsafeReferenceAndRevokedBoard() throws {
        let (shot, board, brief) = try fixture()
        for path in ["../secret.png", "/tmp/board.png", "file:///tmp/board.png", "C:/board.png"] {
            #expect(throws: ProductionImageJobPlanning.Failure.self) {
                try ProductionImageJobPlanning.awaitingConsent(
                    brief: brief, shot: shot, board: board, approvedBoardIDs: [board.id],
                    projectID: UUID(), jobID: UUID(), providerID: "mock",
                    modelID: "fixture", boardRelativePath: path, createdAt: Date())
            }
        }
        #expect(throws: ProductionImagePlanningError.staleBoard) {
            try ProductionImageJobPlanning.awaitingConsent(
                brief: brief, shot: shot, board: board, approvedBoardIDs: [],
                projectID: UUID(), jobID: UUID(), providerID: "mock",
                modelID: "fixture", boardRelativePath: "Board Images/board.png",
                createdAt: Date())
        }
    }
}
