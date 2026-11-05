import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Recover interrupted image completion")
struct ProductionImageInterruptedCompletionRecoveryTests {
    private func png(_ width: Int) throws -> Data {
        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(image.representation(using: .png, properties: [:]))
    }

    private func fixture() async throws -> (
        root: URL, documentURL: URL, shot: Shot, board: BoardFrame,
        approval: ProductionBoardApproval, controller: GenerationJobController,
        jobID: UUID, start: Date
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let image = try png(1)
        let path = root.appendingPathComponent("Board Images/source.png")
        try image.write(to: path)
        let sha = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let projectID = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Cat Island sunrise")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S1",
                               frameNumber: 1, label: "Wide", durationSeconds: 5)
        let selected = BoardImageVersion(fileURL: path, sha256: sha,
                                         prompt: "board", model: "fixture")
        board.imageVersions = [selected]; board.selectedImageID = selected.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: projectID, shot: shot, board: board)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Preserve framing", style: "Painterly",
            boardRelativePath: "Board Images/source.png", projectRoot: root,
            providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true, jobID: UUID(), at: start)
        let controller = try GenerationJobController(
            projectID: projectID, storageURL: root.appendingPathComponent("jobs.json"))
        let service = ProductionImageConsentCoordinator(controller: controller)
        let preview = try await service.stage(staged)
        _ = try await service.authorize(
            staged: staged, displayedPreview: preview, explicitSendApproval: true,
            approval: approval, shot: shot, board: board, projectRoot: root,
            providerAcceptsReferenceImages: true, at: start.addingTimeInterval(1))
        try await controller.markSubmitted(
            jobID: staged.job.id, at: start.addingTimeInterval(2))
        return (root, root.appendingPathComponent("film.json"), shot,
                board, approval, controller, staged.job.id, start)
    }

    @Test func preservedRunningJobCanBeCompletedAndRecoveredAfterRestart() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let generated = try png(2)
        _ = try ProductionImageResultVault.store(
            generated, projectID: f.approval.projectID, jobID: f.jobID, root: f.root)
        let restarted = try GenerationJobController(
            projectID: f.approval.projectID,
            storageURL: f.root.appendingPathComponent("jobs.json"))
        let before = await restarted.snapshot()
        #expect(before.jobs[0].status == .running)
        try await ProductionImageInterruptedCompletionRecovery.completeFromVault(
            controller: restarted, jobID: f.jobID,
            approval: f.approval, shot: f.shot, board: f.board,
            recoveryRoot: f.root, at: f.start.addingTimeInterval(3))
        let after = await restarted.snapshot()
        #expect(after.jobs[0].status == .succeeded)
        #expect(after.jobs[0].completedAt != nil)
        let candidate = try await ProductionImageCompletedResultRecovery.candidate(
            controller: restarted, jobID: f.jobID, approval: f.approval,
            shot: f.shot, board: f.board, documentURL: f.documentURL,
            recoveryRoot: f.root, takeID: UUID())
        #expect(candidate.status == .candidate)
        #expect(candidate.provenance.generationJobID == f.jobID)
        let updated = try ProductionImageCandidateAdoption.appending(candidate, to: [f.board])
        #expect(updated[0].selectedImageID == f.board.selectedImageID)
        #expect(updated[0].durationSeconds == f.board.durationSeconds)
        #expect(updated[0].imageVersions.count == 2)
        #expect(try BoardImageStorage.read(try #require(updated[0].imageVersions.last)) == generated)
    }

    @Test func absentOutputCannotAdvanceRunningJob() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        do {
            try await ProductionImageInterruptedCompletionRecovery.completeFromVault(
                controller: f.controller, jobID: f.jobID, approval: f.approval,
                shot: f.shot, board: f.board, recoveryRoot: f.root, at: Date())
            Issue.record("Cannot record success without preserved media.")
        } catch {
            #expect(error as? ProductionImageInterruptedCompletionRecovery.Failure == .missingPreservedOutput)
        }
        let status = await f.controller.snapshot()
        #expect(status.jobs[0].status == .running)
    }

    @Test func changedBoardCannotReconcileOrModifyJob() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try ProductionImageResultVault.store(
            try png(2), projectID: f.approval.projectID, jobID: f.jobID, root: f.root)
        var altered = f.board
        altered.notes = "New direction"
        do {
            try await ProductionImageInterruptedCompletionRecovery.completeFromVault(
                controller: f.controller, jobID: f.jobID, approval: f.approval,
                shot: f.shot, board: altered, recoveryRoot: f.root, at: Date())
            Issue.record("Changed board must block reconciliation.")
        } catch {
            #expect(error is ProductionBoardApprovalError)
        }
        let status = await f.controller.snapshot()
        #expect(status.jobs[0].status == .running)
    }
}
