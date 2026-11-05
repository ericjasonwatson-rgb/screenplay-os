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
        recoveryRoot: URL? = nil,
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

        // A thrown transport call does not prove the provider rejected the
        // request. It may have received and billed it before the connection
        // failed. Keep the durable job RUNNING and surface it as unresolved;
        // never automatically re-send or mark it failed on network uncertainty.
        let response = try await transport.perform(ready)

        let png: Data
        do {
            png = try OpenAIReferenceImageResponse.decode(response)
        } catch {
            // A returned response with invalid image data cannot be adopted.
            // Preserve only a sanitized error, never raw provider content.
            try? await controller.markFailed(
                jobID: ready.jobID, at: completedAt,
                sanitizedError: "Provider returned an invalid image response. Check usage before retrying."
            )
            throw error
        }

        // If vault persistence fails, leave the job RUNNING. A preserved
        // result might exist despite a filesystem/ledger error, and charging
        // another request is not a safe recovery mechanism.
        let root = try recoveryRoot ?? ProductionImageResultVault.defaultRoot()
        try ProductionImageResultVault.store(
            png, projectID: staged.job.projectID, jobID: ready.jobID,
            root: root)
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
