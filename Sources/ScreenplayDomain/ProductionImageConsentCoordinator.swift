import Foundation

/// Durable consent coordination for an approved-board image job. This actor
/// does not send an HTTP request, attach credentials or mark a job submitted.
/// Call `authorize` only from an actual user-initiated confirmation handler.
public actor ProductionImageConsentCoordinator {
    public enum Failure: Error, Equatable {
        case jobChanged
        case missingCurrentApproval
        case notAwaitingConsent
    }

    private let controller: GenerationJobController

    public init(controller: GenerationJobController) {
        self.controller = controller
    }

    /// Persist an awaiting-consent job before showing a confirmation dialog.
    /// The caller must already have built its exact board/media review via
    /// ApprovedProductionImageFlow.prepare.
    @discardableResult
    public func stage(_ staged: ApprovedProductionImageReview) async throws -> GenerationConsentPreview {
        guard staged.job.status == .awaitingConsent,
              staged.job.consentedAt == nil,
              staged.job.submittedAt == nil,
              staged.job.id == staged.reference.jobID,
              staged.job.requestSHA256 == staged.reference.requestSHA256,
              staged.job.projectID == controller.projectID else {
            throw Failure.jobChanged
        }
        try await controller.add(staged.job)
        return try await controller.consentPreview(for: staged.job.id)
    }

    /// The only way this coordinator records image-generation consent.
    /// Stale jobs and revoked approvals must fail before durable state changes.
    /// Returns an offline proof, not permission for automatic background sends.
    public func authorize(
        staged: ApprovedProductionImageReview,
        displayedPreview: GenerationConsentPreview,
        explicitSendApproval: Bool,
        approval: ProductionBoardApproval,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL,
        providerAcceptsReferenceImages: Bool,
        at date: Date
    ) async throws -> ProductionImageSendAuthorization {
        let ledger = await controller.snapshot()
        guard let durable = ledger.jobs.first(where: { $0.id == staged.job.id }),
              durable == staged.job,
              durable.status == .awaitingConsent,
              displayedPreview == GenerationConsentPreview(job: durable) else {
            throw Failure.jobChanged
        }
        let proof = try ProductionImageSendGate.authorize(
            staged: staged,
            consentPreview: displayedPreview,
            explicitSendApproval: explicitSendApproval,
            approval: approval, projectID: controller.projectID,
            shot: shot, board: board, projectRoot: projectRoot,
            providerAcceptsReferenceImages: providerAcceptsReferenceImages,
            at: date)
        // Granting consent requires the controller to compare the exact same
        // frozen preview before persisting the queued transition.
        try await controller.grantConsent(
            for: staged.job.id, matching: displayedPreview, at: date)
        return proof
    }

    /// Explicit cancellation remains available while the job is awaiting
    /// consent or queued; never dispatch automatically on recovery.
    public func cancel(jobID: UUID, at date: Date) async throws {
        try await controller.cancel(jobID: jobID, at: date)
    }
}
