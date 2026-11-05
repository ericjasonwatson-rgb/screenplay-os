import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain

@Suite("Durable production image consent coordination")
struct ProductionImageConsentCoordinatorTests {
    private func fixture() throws -> (
        root: URL, projectID: UUID, shot: Shot, board: BoardFrame,
        approval: ProductionBoardApproval, staged: ApprovedProductionImageReview,
        controller: GenerationJobController
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = root.appendingPathComponent("Board Images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = images.appendingPathComponent("board.png")
        try bytes.write(to: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let project = UUID()
        let shot = Shot(sceneSpineID: "S001", label: "Beach wide")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S001",
                               frameNumber: 1, label: "Approved sketch", durationSeconds: 4)
        let image = BoardImageVersion(fileURL: url, sha256: digest,
                                      prompt: "Storyboard", model: "fixture")
        board.imageVersions = [image]
        board.selectedImageID = image.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: project, shot: shot, board: board)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: project, shot: shot, board: board,
            instruction: "Keep this blocking", style: "Warm naturalistic",
            boardRelativePath: "Board Images/board.png", projectRoot: root,
            providerID: "fixture", modelID: "fixture",
            providerAcceptsReferenceImages: true, jobID: UUID(),
            at: Date(timeIntervalSince1970: 1_700_000_000))
        let controller = try GenerationJobController(
            projectID: project, storageURL: root.appendingPathComponent("jobs.json"))
        return (root, project, shot, board, approval, staged, controller)
    }

    @Test func stageThenExplicitConsentPersistsOnlyQueuedNotSubmitted() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let coordinator = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await coordinator.stage(f.staged)
        let before = await f.controller.snapshot()
        #expect(before.jobs.count == 1)
        #expect(before.jobs[0].status == .awaitingConsent)
        #expect(before.jobs[0].consentedAt == nil)
        let consentDate = Date(timeIntervalSince1970: 1_700_000_050)
        let proof = try await coordinator.authorize(
            staged: f.staged, displayedPreview: preview,
            explicitSendApproval: true, approval: f.approval,
            shot: f.shot, board: f.board, projectRoot: f.root,
            providerAcceptsReferenceImages: true, at: consentDate)
        #expect(proof.jobID == f.staged.job.id)
        let after = await f.controller.snapshot()
        #expect(after.jobs[0].status == .queued)
        #expect(after.jobs[0].consentedAt == consentDate)
        #expect(after.jobs[0].submittedAt == nil)
        // Persisted state survives controller reconstruction without dispatch.
        let reloaded = try GenerationJobController(
            projectID: f.projectID, storageURL: f.root.appendingPathComponent("jobs.json"))
        let recoveredLedger = await reloaded.snapshot()
        #expect(recoveredLedger.jobs[0].status == .queued)
        #expect(recoveredLedger.jobs[0].submittedAt == nil)
    }

    @Test func decliningSendNeverRecordsConsent() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let coordinator = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await coordinator.stage(f.staged)
        do {
            _ = try await coordinator.authorize(
                staged: f.staged, displayedPreview: preview,
                explicitSendApproval: false, approval: f.approval,
                shot: f.shot, board: f.board, projectRoot: f.root,
                providerAcceptsReferenceImages: true, at: Date())
            Issue.record("Declined consent must not succeed.")
        } catch {
            #expect(error as? ProductionImageSendGateError == .notApprovedForSend)
        }
        let jobs = await f.controller.snapshot()
        #expect(jobs.jobs[0].status == .awaitingConsent)
    }

    @Test func staleBoardNeverQueuesRequest() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let coordinator = ProductionImageConsentCoordinator(controller: f.controller)
        let preview = try await coordinator.stage(f.staged)
        var modified = f.board
        modified.notes = "Change camera"
        do {
            _ = try await coordinator.authorize(
                staged: f.staged, displayedPreview: preview,
                explicitSendApproval: true, approval: f.approval,
                shot: f.shot, board: modified, projectRoot: f.root,
                providerAcceptsReferenceImages: true, at: Date())
            Issue.record("Stale board must not be authorized.")
        } catch {
            #expect(error is ProductionBoardApprovalError)
        }
        let ledger = await f.controller.snapshot()
        #expect(ledger.jobs[0].status == .awaitingConsent)
    }

    @Test func duplicateStagingDoesNotDuplicateJob() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let coordinator = ProductionImageConsentCoordinator(controller: f.controller)
        _ = try await coordinator.stage(f.staged)
        do {
            _ = try await coordinator.stage(f.staged)
            Issue.record("Duplicate job must not be added.")
        } catch {
            #expect(error as? GenerationJobControllerError == .duplicateJobID)
        }
        let ledger = await f.controller.snapshot()
        #expect(ledger.jobs.count == 1)
    }
}
