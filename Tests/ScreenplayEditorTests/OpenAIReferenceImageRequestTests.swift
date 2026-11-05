import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("OpenAI reference image request serialization")
struct OpenAIReferenceImageRequestTests {
    private func fixture(modelID: String = "gpt-image-2.5-flare", providerID: String = "openai")
    throws -> (URL, UUID, Shot, BoardFrame, ProductionBoardApproval, ApprovedProductionImageReview, ProductionImageSendAuthorization) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = root.appendingPathComponent("Board Images/board.png")
        try bytes.write(to: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let project = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Opening")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Board")
        let version = BoardImageVersion(fileURL: url, sha256: digest, prompt: "sketch", model: "mock")
        board.imageVersions = [version]
        board.selectedImageID = version.id
        let approval = try ProductionBoardApprovals.approve(projectID: project, shot: shot, board: board)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: project, shot: shot, board: board,
            instruction: "Golden light", style: "Animated",
            boardRelativePath: "Board Images/board.png", projectRoot: root,
            providerID: providerID, modelID: modelID,
            providerAcceptsReferenceImages: true, jobID: UUID(), at: Date())
        let proof = try ProductionImageSendGate.authorize(
            staged: staged, consentPreview: GenerationConsentPreview(job: staged.job),
            explicitSendApproval: true, approval: approval, projectID: project,
            shot: shot, board: board, projectRoot: root,
            providerAcceptsReferenceImages: true, at: Date())
        return (root, project, shot, board, approval, staged, proof)
    }

    @Test func payloadIncludesExactImageAndNeverContainsCredentials() throws {
        let (root, project, shot, board, approval, staged, proof) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let frozen = try OpenAIReferenceImageRequest.prepare(
            staged: staged, authorization: proof, approval: approval,
            projectID: project, shot: shot, board: board, projectRoot: root)
        #expect(frozen.endpoint.absoluteString == "https://api.openai.com/v1/images/edits")
        let json = try #require(JSONSerialization.jsonObject(with: frozen.body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-image-2.5-flare")
        #expect(json["prompt"] as? String == staged.job.request.prompt)
        #expect(json["output_format"] as? String == "png")
        let images = try #require(json["images"] as? [[String: String]])
        #expect(images.count == 1)
        #expect(images[0]["image_url"] == "data:image/png;base64," + staged.reference.imageBytes.base64EncodedString())
        #expect(json["Authorization"] == nil && json["api_key"] == nil)
        #expect(frozen.requestSHA256 == staged.job.requestSHA256)
        #expect(frozen.sourceImageSHA256 == staged.reference.imageSHA256)
        #expect(staged.job.status == .awaitingConsent)
    }

    @Test func unsupportedProviderAndModelFailClosed() throws {
        let (root, project, shot, board, approval, staged, proof) = try fixture(modelID: "unknown-model")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: OpenAIReferenceImageRequest.Failure.unsupportedModel) {
            try OpenAIReferenceImageRequest.prepare(
                staged: staged, authorization: proof, approval: approval,
                projectID: project, shot: shot, board: board, projectRoot: root)
        }
        let other = try fixture(providerID: "mock")
        defer { try? FileManager.default.removeItem(at: other.0) }
        #expect(throws: OpenAIReferenceImageRequest.Failure.wrongProvider) {
            try OpenAIReferenceImageRequest.prepare(
                staged: other.5, authorization: other.6, approval: other.4,
                projectID: other.1, shot: other.2, board: other.3, projectRoot: other.0)
        }
    }

    @Test func changedBoardCannotBeSerialized() throws {
        let (root, project, shot, board, approval, staged, proof) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var changed = board
        changed.notes = "New framing"
        #expect(throws: ProductionBoardApprovalError.self) {
            try OpenAIReferenceImageRequest.prepare(
                staged: staged, authorization: proof, approval: approval,
                projectID: project, shot: shot, board: changed, projectRoot: root)
        }
    }
}
