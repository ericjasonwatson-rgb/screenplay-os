import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Reference-image result preparation")
struct ProductionImageResultPreparationTests {
    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func response(_ png: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": png.base64EncodedString()]]
        ])
    }

    private func fixture() throws -> (
        root: URL, documentURL: URL, shot: Shot, board: BoardFrame,
        approval: ProductionBoardApproval, staged: ApprovedProductionImageReview,
        succeeded: GenerationJobRecord
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let original = try png()
        let imageURL = root.appendingPathComponent("Board Images/approved.png")
        try original.write(to: imageURL)
        let sha = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let projectID = UUID()
        let shot = Shot(sceneSpineID: "S001", label: "Beach wide", notes: "Static")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S001", frameNumber: 1,
                               label: "Approved board", durationSeconds: 4.5)
        let selected = BoardImageVersion(fileURL: imageURL, sha256: sha,
                                         prompt: "pencil sketch", model: "fixture")
        board.imageVersions = [selected]
        board.selectedImageID = selected.id
        let approval = try ProductionBoardApprovals.approve(projectID: projectID,
                                                             shot: shot, board: board)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Golden light, preserve framing", style: "Painted animation",
            boardRelativePath: "Board Images/approved.png", projectRoot: root,
            providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true, jobID: UUID(), at: created)
        var succeeded = staged.job
        succeeded.status = .succeeded
        succeeded.consentedAt = created.addingTimeInterval(1)
        succeeded.submittedAt = created.addingTimeInterval(2)
        succeeded.completedAt = created.addingTimeInterval(3)
        succeeded.updatedAt = created.addingTimeInterval(3)
        let documentURL = root.appendingPathComponent("Test.screenplayos.json")
        return (root, documentURL, shot, board, approval, staged, succeeded)
    }

    @Test func decodesStrictSingleImageResponse() throws {
        let bytes = try png()
        #expect(try OpenAIReferenceImageResponse.decode(response(bytes)) == bytes)
        let malformed = Data(#"{"data":[{"b64_json":"not-base64"}]}"#.utf8)
        #expect(throws: OpenAIReferenceImageResponse.Failure.self) {
            try OpenAIReferenceImageResponse.decode(malformed)
        }
        let multi = try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": bytes.base64EncodedString()],
                     ["b64_json": bytes.base64EncodedString()]]
        ])
        #expect(throws: OpenAIReferenceImageResponse.Failure.self) {
            try OpenAIReferenceImageResponse.decode(multi)
        }
        let remote = Data(#"{"data":[{"url":"https://example.com/a.png"}]}"#.utf8)
        #expect(throws: OpenAIReferenceImageResponse.Failure.self) {
            try OpenAIReferenceImageResponse.decode(remote)
        }
    }

    @Test func completedJobCreatesUnselectedTakeWithoutChangingBoard() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let originalBoard = f.board
        let output = try png()
        let id = UUID()
        let take = try ProductionImageResultPreparation.prepare(
            response: response(output), job: f.succeeded, staged: f.staged,
            currentShot: f.shot, currentBoard: f.board, approval: f.approval,
            documentURL: f.documentURL, takeID: id, now: Date())
        #expect(take.id == id)
        #expect(take.kind == .generatedImage)
        #expect(take.status == .candidate)
        #expect(take.shotID == f.shot.id)
        #expect(take.boardFrameID == f.board.id)
        #expect(take.durationSeconds == f.board.durationSeconds)
        #expect(take.provenance.generationJobID == f.succeeded.id)
        #expect(take.provenance.promptSHA256 == f.staged.brief.promptSHA256)
        #expect(take.sha256 == BoardImageStorage.digest(output))
        #expect(try Data(contentsOf: take.mediaURL) == output)
        #expect(f.board == originalBoard)
    }

    @Test func unsubmittedOrCancelledJobCannotProduceTake() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let bytes = try response(png())
        #expect(throws: ProductionImageResultPreparation.Failure.jobNotCompleted) {
            try ProductionImageResultPreparation.prepare(
                response: bytes, job: f.staged.job, staged: f.staged,
                currentShot: f.shot, currentBoard: f.board, approval: f.approval,
                documentURL: f.documentURL, takeID: UUID(), now: Date())
        }
        var wrong = f.succeeded
        wrong.modelID = "different-model"
        #expect(throws: ProductionImageResultPreparation.Failure.mismatchedJob) {
            try ProductionImageResultPreparation.prepare(
                response: bytes, job: wrong, staged: f.staged,
                currentShot: f.shot, currentBoard: f.board, approval: f.approval,
                documentURL: f.documentURL, takeID: UUID(), now: Date())
        }
    }

    @Test func changedBoardCannotCreateCandidate() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var changed = f.board
        changed.notes = "Changed shot"
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionImageResultPreparation.prepare(
                response: response(png()), job: f.succeeded, staged: f.staged,
                currentShot: f.shot, currentBoard: changed, approval: f.approval,
                documentURL: f.documentURL, takeID: UUID(), now: Date())
        }
    }
}
