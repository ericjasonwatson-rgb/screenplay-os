import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Recover completed paid image without another provider request")
struct ProductionImageCompletedResultRecoveryTests {
    private func png(_ width: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func fixture() async throws -> (
        URL, URL, Shot, BoardFrame, ProductionBoardApproval,
        GenerationJobController, UUID
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let image = try png(1)
        let initialFile = root.appendingPathComponent("Board Images/source.png")
        try image.write(to: initialFile)
        let sha = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let project = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Cat Island wide")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S1",
                               frameNumber: 1, label: "Approved board", durationSeconds: 5)
        let version = BoardImageVersion(fileURL: initialFile, sha256: sha,
                                        prompt: "sketch", model: "fixture")
        board.imageVersions = [version]; board.selectedImageID = version.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: project, shot: shot, board: board)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: project, shot: shot, board: board,
            instruction: "Preserve framing", style: "Painterly",
            boardRelativePath: "Board Images/source.png", projectRoot: root,
            providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true,
            jobID: UUID(), at: created)
        let controller = try GenerationJobController(
            projectID: project, storageURL: root.appendingPathComponent("jobs.json"))
        let coordinator = ProductionImageConsentCoordinator(controller: controller)
        let consent = try await coordinator.stage(staged)
        _ = try await coordinator.authorize(
            staged: staged, displayedPreview: consent,
            explicitSendApproval: true, approval: approval,
            shot: shot, board: board, projectRoot: root,
            providerAcceptsReferenceImages: true, at: created.addingTimeInterval(1))
        try await controller.markSubmitted(jobID: staged.job.id, at: created.addingTimeInterval(2))
        try ProductionImageResultVault.store(try png(2), projectID: project,
                                              jobID: staged.job.id, root: root)
        try await controller.markSucceeded(jobID: staged.job.id, at: created.addingTimeInterval(3))
        return (root, root.appendingPathComponent("film.json"), shot, board,
                approval, controller, staged.job.id)
    }

    @Test func completedJobRecoversFromVaultWithoutSending() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.0) }
        let original = f.3
        let take = try await ProductionImageCompletedResultRecovery.candidate(
            controller: f.5, jobID: f.6, approval: f.4,
            shot: f.2, board: f.3, documentURL: f.1,
            recoveryRoot: f.0, takeID: UUID())
        #expect(take.status == .candidate)
        #expect(take.shotID == f.2.id && take.boardFrameID == f.3.id)
        #expect(take.durationSeconds == f.3.durationSeconds)
        #expect(take.provenance.generationJobID == f.6)
        #expect(f.3 == original)
        let projected = try ProductionImageCandidateAdoption.appending(take, to: [f.3])
        #expect(projected[0].selectedImageID == original.selectedImageID)
        #expect(projected[0].imageVersions.count == 2)
        #expect(try BoardImageStorage.read(try #require(projected[0].imageVersions.last)) == (try png(2)))
    }

    @Test func missingJobAndChangedBoardCannotRecover() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.0) }
        do {
            _ = try await ProductionImageCompletedResultRecovery.candidate(
                controller: f.5, jobID: UUID(), approval: f.4,
                shot: f.2, board: f.3, documentURL: f.1,
                recoveryRoot: f.0, takeID: UUID())
            Issue.record("Unknown job must not recover an image.")
        } catch {
            #expect(error as? ProductionImageCompletedResultRecovery.Failure == .missingCompletedJob)
        }
        var edited = f.3
        edited.notes = "Different composition"
        do {
            _ = try await ProductionImageCompletedResultRecovery.candidate(
                controller: f.5, jobID: f.6, approval: f.4,
                shot: f.2, board: edited, documentURL: f.1,
                recoveryRoot: f.0, takeID: UUID())
            Issue.record("Edited board cannot adopt the old approved result.")
        } catch {
            #expect(error is ProductionBoardApprovalError)
        }
    }
}
