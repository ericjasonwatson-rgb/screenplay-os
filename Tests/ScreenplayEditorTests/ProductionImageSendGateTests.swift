import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain

@Suite("Production image explicit send gate")
struct ProductionImageSendGateTests {
    private func fixture() throws -> (URL, UUID, Shot, BoardFrame, ProductionBoardApproval, ApprovedProductionImageReview) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Board Images"),
                                                 withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
        let imageURL = root.appendingPathComponent("Board Images/board.png")
        try bytes.write(to: imageURL)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let project = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Opening beach")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S1",
                               frameNumber: 1, label: "Approved board")
        let image = BoardImageVersion(fileURL: imageURL, sha256: digest,
                                       prompt: "sketch", model: "mock")
        board.imageVersions = [image]
        board.selectedImageID = image.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: project, shot: shot, board: board)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: project, shot: shot, board: board,
            instruction: "Golden lighting", style: "Animation",
            boardRelativePath: "Board Images/board.png", projectRoot: root,
            providerID: "mock", modelID: "fixture", providerAcceptsReferenceImages: true,
            jobID: UUID(), at: Date())
        return (root, project, shot, board, approval, staged)
    }

    @Test func noApprovalCannotProduceAuthorization() throws {
        let (root, project, shot, board, approval, staged) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ProductionImageSendGateError.notApprovedForSend) {
            try ProductionImageSendGate.authorize(
                staged: staged, consentPreview: GenerationConsentPreview(job: staged.job),
                explicitSendApproval: false, approval: approval, projectID: project,
                shot: shot, board: board, projectRoot: root,
                providerAcceptsReferenceImages: true, at: Date())
        }
    }

    @Test func consentIsSpecificToExactJobAndCanBeRevalidated() throws {
        let (root, project, shot, board, approval, staged) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let consent = GenerationConsentPreview(job: staged.job)
        let authorization = try ProductionImageSendGate.authorize(
            staged: staged, consentPreview: consent, explicitSendApproval: true,
            approval: approval, projectID: project, shot: shot, board: board,
            projectRoot: root, providerAcceptsReferenceImages: true, at: Date())
        #expect(authorization.jobID == staged.job.id)
        #expect(authorization.requestSHA256 == staged.job.requestSHA256)
        try ProductionImageSendGate.revalidate(
            authorization, staged: staged, approval: approval, projectID: project,
            shot: shot, board: board, projectRoot: root, providerAcceptsReferenceImages: true)

        var edited = board
        edited.notes = "Change blocking"
        #expect(throws: ProductionBoardApprovalError.self) {
            try ProductionImageSendGate.revalidate(
                authorization, staged: staged, approval: approval, projectID: project,
                shot: shot, board: edited, projectRoot: root,
                providerAcceptsReferenceImages: true)
        }
    }

    @Test func consentForAnotherJobCannotAuthorizeThisOne() throws {
        let (root, project, shot, board, approval, staged) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = GenerationJobRecord(
            id: UUID(), projectID: project, capability: .image,
            providerID: staged.job.providerID, modelID: staged.job.modelID,
            target: staged.job.target, request: staged.job.request,
            requestSHA256: staged.job.requestSHA256,
            status: .awaitingConsent, createdAt: Date(), updatedAt: Date())
        #expect(throws: ProductionImageSendGateError.changedRequest) {
            try ProductionImageSendGate.authorize(
                staged: staged, consentPreview: GenerationConsentPreview(job: other),
                explicitSendApproval: true, approval: approval, projectID: project,
                shot: shot, board: board, projectRoot: root,
                providerAcceptsReferenceImages: true, at: Date())
        }
    }
}
