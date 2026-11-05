import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Reference-image dispatch preflight")
struct ProductionImageDispatchPreflightTests {
    private func fixture() throws -> (
        root: URL, projectID: UUID, shot: Shot, board: BoardFrame,
        approval: ProductionBoardApproval, staged: ApprovedProductionImageReview,
        controller: GenerationJobController
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(rep.representation(using: .png, properties: [:]))
        let file = root.appendingPathComponent("Board Images/ref.png")
        try image.write(to: file)
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let projectID = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Beach")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S1", frameNumber: 1,
                               label: "Beach board")
        let version = BoardImageVersion(fileURL: file, sha256: digest, prompt: "board", model: "test")
        board.imageVersions = [version]; board.selectedImageID = version.id
        let approval = try ProductionBoardApprovals.approve(projectID: projectID, shot: shot, board: board)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Keep framing", style: "Warm light",
            boardRelativePath: "Board Images/ref.png", projectRoot: root,
            providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true, jobID: UUID(),
            at: Date(timeIntervalSince1970: 1_700_000_000))
        let controller = try GenerationJobController(projectID: projectID,
            storageURL: root.appendingPathComponent("jobs.json"))
        return (root, projectID, shot, board, approval, staged, controller)
    }

    @Test func cannotPrepareUntilDurableConsent() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await service.stage(f.staged)
        let proof = try ProductionImageSendGate.authorize(
            staged: f.staged, consentPreview: preview, explicitSendApproval: true,
            approval: f.approval, projectID: f.projectID, shot: f.shot,
            board: f.board, projectRoot: f.root,
            providerAcceptsReferenceImages: true, at: Date())
        do {
            _ = try await ProductionImageDispatchPreflight.prepare(
                controller: f.controller, staged: f.staged, authorization: proof,
                approval: f.approval, projectID: f.projectID, shot: f.shot,
                board: f.board, projectRoot: f.root)
            Issue.record("Unconsented job unexpectedly passed preflight.")
        } catch {
            #expect(error as? ProductionImageDispatchPreflight.Failure == .missingDurableConsent)
        }
    }

    @Test func consentedJobIsOfflineReadyButNotSubmitted() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await service.stage(f.staged)
        let proof = try await service.authorize(
            staged: f.staged, displayedPreview: preview,
            explicitSendApproval: true, approval: f.approval,
            shot: f.shot, board: f.board, projectRoot: f.root,
            providerAcceptsReferenceImages: true, at: Date(timeIntervalSince1970: 1_700_000_010))
        let ready = try await ProductionImageDispatchPreflight.prepare(
            controller: f.controller, staged: f.staged, authorization: proof,
            approval: f.approval, projectID: f.projectID, shot: f.shot,
            board: f.board, projectRoot: f.root)
        #expect(ready.jobID == f.staged.job.id)
        #expect(ready.endpoint.absoluteString == "https://api.openai.com/v1/images/edits")
        #expect(ready.requestSHA256 == f.staged.job.requestSHA256)
        #expect(!ready.body.isEmpty)
        let after = await f.controller.snapshot()
        #expect(after.jobs[0].status == .queued)
        #expect(after.jobs[0].submittedAt == nil)
    }

    @Test func recoveredQueuedJobRequiresReviewAndCannotAutoSend() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await service.stage(f.staged)
        let proof = try await service.authorize(
            staged: f.staged, displayedPreview: preview,
            explicitSendApproval: true, approval: f.approval,
            shot: f.shot, board: f.board, projectRoot: f.root,
            providerAcceptsReferenceImages: true, at: Date(timeIntervalSince1970: 1_700_000_010))
        let recovered = try GenerationJobController(
            projectID: f.projectID, storageURL: f.root.appendingPathComponent("jobs.json"))
        do {
            _ = try await ProductionImageDispatchPreflight.prepare(
                controller: recovered, staged: f.staged, authorization: proof,
                approval: f.approval, projectID: f.projectID, shot: f.shot,
                board: f.board, projectRoot: f.root)
            Issue.record("Recovered queued job must remain blocked.")
        } catch {
            #expect(error as? ProductionImageDispatchPreflight.Failure == .recoveryReviewRequired)
        }
    }

    @Test func changedImageAndCancelledJobAreBlocked() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await service.stage(f.staged)
        let proof = try await service.authorize(
            staged: f.staged, displayedPreview: preview,
            explicitSendApproval: true, approval: f.approval,
            shot: f.shot, board: f.board, projectRoot: f.root,
            providerAcceptsReferenceImages: true, at: Date(timeIntervalSince1970: 1_700_000_010))
        try Data([0, 1, 2]).write(to: f.root.appendingPathComponent("Board Images/ref.png"))
        do {
            _ = try await ProductionImageDispatchPreflight.prepare(
                controller: f.controller, staged: f.staged, authorization: proof,
                approval: f.approval, projectID: f.projectID, shot: f.shot,
                board: f.board, projectRoot: f.root)
            Issue.record("Changed media must be rejected.")
        } catch {
            #expect(error is ProductionImageReferenceReviewError)
        }
        try await service.cancel(jobID: f.staged.job.id, at: Date(timeIntervalSince1970: 1_700_000_020))
        do {
            _ = try await ProductionImageDispatchPreflight.prepare(
                controller: f.controller, staged: f.staged, authorization: proof,
                approval: f.approval, projectID: f.projectID, shot: f.shot,
                board: f.board, projectRoot: f.root)
            Issue.record("Cancelled job must not be sent.")
        } catch {
            #expect(error as? ProductionImageDispatchPreflight.Failure == .missingDurableConsent)
        }
    }
}
