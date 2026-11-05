import Foundation
import ScreenplayDomain

/// Injected boundary for an explicitly user-initiated provider request.
/// The production app does not register any live implementation of this
/// protocol. Deterministic test transports return a single canned response.
@MainActor
protocol ProductionImageResponseTransport {
    func perform(_ prepared: ProductionImageDispatchPreflight.Ready) async throws -> Data
}

/// Coordinates a verified, durable job with one transport response.
/// Never selects a board image, inserts a Take or retries a provider request.
/// A caller must invoke this only from an explicit Send action, following
/// review/approval, and supply a verified transport implementation.
@MainActor
enum ProductionImageResponseExecution {
    enum Failure: Error, Equatable {
        case cancelledBeforeSend
    }

    static func execute(
        controller: GenerationJobController,
        staged: ApprovedProductionImageReview,
        authorization: ProductionImageSendAuthorization,
        approval: ProductionBoardApproval,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL,
        documentURL: URL,
        takeID: UUID,
        submittedAt: Date,
        completedAt: Date,
        transport: any ProductionImageResponseTransport
    ) async throws -> Take {
        // Everything before submission is local; an expired preview or
        // recovered queued job must fail without touching provider transport.
        let ready = try await ProductionImageDispatchPreflight.prepare(
            controller: controller, staged: staged,
            authorization: authorization, approval: approval,
            projectID: staged.job.projectID, shot: shot,
            board: board, projectRoot: projectRoot
        )
        guard !Task.isCancelled else { throw Failure.cancelledBeforeSend }
        // Durable submission is recorded immediately before the single
        // transport invocation. Re-entry fails at the controller's queued gate.
        try await controller.markSubmitted(jobID: ready.jobID, at: submittedAt)

        let response: Data
        do {
            response = try await transport.perform(ready)
            // Validate the provider result before marking it successful.
            _ = try OpenAIReferenceImageResponse.decode(response)
        } catch {
            // Provider error text can contain credentials, prompts or media.
            // Never persist arbitrary error descriptions from this boundary.
            try? await controller.markFailed(
                jobID: ready.jobID, at: completedAt,
                sanitizedError: "Reference-image request failed or returned invalid image data."
            )
            throw error
        }
        try await controller.markSucceeded(jobID: ready.jobID, at: completedAt)
        // This reads the actual persisted succeeded job. If project approval
        // changed in flight, it rejects the candidate without editing Boards.
        return try await ProductionImageResultPreparation.prepareFromPersistedJob(
            response: response, controller: controller,
            staged: staged, currentShot: shot, currentBoard: board,
            approval: approval, documentURL: documentURL,
            takeID: takeID, now: completedAt
        )
    }
}
