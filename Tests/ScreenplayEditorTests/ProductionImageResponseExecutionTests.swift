import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production-image injected transport lifecycle")
@MainActor
struct ProductionImageResponseExecutionTests {
    private struct Fixture {
        let root: URL
        let documentURL: URL
        let shot: Shot
        let board: BoardFrame
        let approval: ProductionBoardApproval
        let staged: ApprovedProductionImageReview
        let authorization: ProductionImageSendAuthorization
        let controller: GenerationJobController
        let started: Date
    }

    private enum FixtureFailure: Error { case serviceUnavailable }

    @MainActor
    private final class FixtureTransport: ProductionImageResponseTransport {
        var calls = 0
        let response: Data?
        init(response: Data?) { self.response = response }
        func perform(_ prepared: ProductionImageDispatchPreflight.Ready) async throws -> Data {
            calls += 1
            #expect(prepared.endpoint.absoluteString == "https://api.openai.com/v1/images/edits")
            #expect(!prepared.body.isEmpty)
            guard let response else { throw FixtureFailure.serviceUnavailable }
            return response
        }
    }

    private func png(_ width: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let initial = try png(1)
        let file = root.appendingPathComponent("Board Images/ref.png")
        try initial.write(to: file)
        let digest = SHA256.hash(data: initial).map { String(format: "%02x", $0) }.joined()
        let projectID = UUID()
        let shot = Shot(sceneSpineID: "S1", label: "Cat Island opening")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
            frameNumber: 1, label: "Opening", durationSeconds: 4)
        let image = BoardImageVersion(fileURL: file, sha256: digest,
                                      prompt: "rough board", model: "fixture")
        board.imageVersions = [image]; board.selectedImageID = image.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: projectID, shot: shot, board: board)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Maintain composition", style: "Painted",
            boardRelativePath: "Board Images/ref.png", projectRoot: root,
            providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true,
            jobID: UUID(), at: started)
        let controller = try GenerationJobController(
            projectID: projectID, storageURL: root.appendingPathComponent("jobs.json"))
        let coordinator = ProductionImageConsentCoordinator(controller: controller)
        let preview = try await coordinator.stage(staged)
        let authorization = try await coordinator.authorize(
            staged: staged, displayedPreview: preview,
            explicitSendApproval: true, approval: approval, shot: shot,
            board: board, projectRoot: root,
            providerAcceptsReferenceImages: true,
            at: started.addingTimeInterval(1))
        return Fixture(root: root, documentURL: root.appendingPathComponent("film.json"),
            shot: shot, board: board, approval: approval, staged: staged,
            authorization: authorization, controller: controller, started: started)
    }

    @Test func oneSuccessfulOfflineTransportCreatesUnselectedCandidate() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let image = try png(2)
        let response = try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": image.base64EncodedString()]]
        ])
        let transport = FixtureTransport(response: response)
        let original = f.board
        let take = try await ProductionImageResponseExecution.execute(
            controller: f.controller, staged: f.staged, authorization: f.authorization,
            approval: f.approval, shot: f.shot, board: f.board, projectRoot: f.root,
            documentURL: f.documentURL, takeID: UUID(),
            submittedAt: f.started.addingTimeInterval(2),
            completedAt: f.started.addingTimeInterval(3),
            recoveryRoot: f.root, transport: transport)
        #expect(transport.calls == 1)
        #expect(take.status == .candidate)
        #expect(take.shotID == f.shot.id && take.boardFrameID == f.board.id)
        #expect(take.durationSeconds == f.board.durationSeconds)
        #expect(take.provenance.generationJobID == f.staged.job.id)
        #expect(f.board == original)
        // A provider response is preserved independently of adding it to Boards,
        // and can be recovered without executing the transport again.
        let recoveredResult = try ProductionImageResultVault.recoverResponse(
            projectID: f.staged.job.projectID, jobID: f.staged.job.id, root: f.root)
        #expect(try OpenAIReferenceImageResponse.decode(recoveredResult) == image)
        let ledger = await f.controller.snapshot()
        #expect(ledger.jobs[0].status == .succeeded)
        #expect(ledger.jobs[0].submittedAt != nil)
        do {
            _ = try await ProductionImageResponseExecution.execute(
                controller: f.controller, staged: f.staged, authorization: f.authorization,
                approval: f.approval, shot: f.shot, board: f.board, projectRoot: f.root,
                documentURL: f.documentURL, takeID: UUID(),
                submittedAt: f.started.addingTimeInterval(4),
                completedAt: f.started.addingTimeInterval(5),
                recoveryRoot: f.root, transport: transport)
            Issue.record("Completed job should not be dispatched twice.")
        } catch {
            #expect(error is ProductionImageDispatchPreflight.Failure)
        }
        #expect(transport.calls == 1)
    }

    @Test func invalidResponseFailsJobWithoutCreatingMedia() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let transport = FixtureTransport(response: Data(#"{"data":[{"b64_json":"not-base64"}]}"#.utf8))
        do {
            _ = try await ProductionImageResponseExecution.execute(
                controller: f.controller, staged: f.staged, authorization: f.authorization,
                approval: f.approval, shot: f.shot, board: f.board, projectRoot: f.root,
                documentURL: f.documentURL, takeID: UUID(),
                submittedAt: f.started.addingTimeInterval(2),
                completedAt: f.started.addingTimeInterval(3),
                recoveryRoot: f.root, transport: transport)
            Issue.record("Malformed provider response must be rejected.")
        } catch {
            #expect(error is OpenAIReferenceImageResponse.Failure)
        }
        let ledger = await f.controller.snapshot()
        #expect(ledger.jobs[0].status == .failed)
        #expect(ledger.jobs[0].sanitizedError == "Provider returned an invalid image response. Check usage before retrying.")
        #expect(transport.calls == 1)
        #expect(f.board.imageVersions.count == 1)
    }

    @Test func uncertainTransportOutcomeStaysRunningWithoutRetry() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let transport = FixtureTransport(response: nil)
        do {
            _ = try await ProductionImageResponseExecution.execute(
                controller: f.controller, staged: f.staged, authorization: f.authorization,
                approval: f.approval, shot: f.shot, board: f.board, projectRoot: f.root,
                documentURL: f.documentURL, takeID: UUID(),
                submittedAt: f.started.addingTimeInterval(2),
                completedAt: f.started.addingTimeInterval(3),
                recoveryRoot: f.root, transport: transport)
            Issue.record("Transport error must not succeed.")
        } catch {
            #expect(error is FixtureFailure)
        }
        let ledger = await f.controller.snapshot()
        #expect(ledger.jobs[0].status == .running)
        #expect(ledger.jobs[0].sanitizedError == nil)
        #expect(ProductionImageUncertainSubmission.isUnresolved(
            ledger.jobs[0], hasPreservedImage: false))
        #expect(transport.calls == 1)
        // An ambiguous request must fail preflight on any attempted reuse.
        do {
            _ = try await ProductionImageResponseExecution.execute(
                controller: f.controller, staged: f.staged,
                authorization: f.authorization, approval: f.approval,
                shot: f.shot, board: f.board, projectRoot: f.root,
                documentURL: f.documentURL, takeID: UUID(),
                submittedAt: f.started.addingTimeInterval(4),
                completedAt: f.started.addingTimeInterval(5),
                recoveryRoot: f.root, transport: transport)
            Issue.record("Ambiguous submission must not retry.")
        } catch {
            #expect(error is ProductionImageDispatchPreflight.Failure)
        }
        #expect(transport.calls == 1)
    }
}
