import CryptoKit
import Foundation
import ScreenplayDomain

/// Offline, one-shot dispatch preflight. This is the final non-network boundary
/// between a durable queued job and the authenticated provider transport.
/// No controller transition, credentials, HTTP request or automatic retry here.
enum ProductionImageDispatchPreflight {
    enum Failure: Error, Equatable {
        case missingDurableConsent
        case jobChanged
        case requestChanged
        case invalidPayload
        case recoveryReviewRequired
    }

    struct Ready: Sendable {
        let jobID: UUID
        let endpoint: URL
        let body: Data
        let bodySHA256: String
        let consentedAt: Date
        let requestSHA256: String
    }

    /// Caller must explicitly initiate this operation from a Send action and
    /// execute provider transport only after independently verifying credentials,
    /// account/model support and any recovery review. This method is offline.
    static func prepare(
        controller: GenerationJobController,
        staged: ApprovedProductionImageReview,
        authorization: ProductionImageSendAuthorization,
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL
    ) async throws -> Ready {
        let ledger = await controller.snapshot()
        guard ledger.projectID == projectID,
              let durable = ledger.jobs.first(where: { $0.id == staged.job.id }),
              durable.status == .queued, durable.consentedAt != nil,
              durable.submittedAt == nil, durable.completedAt == nil else {
            throw Failure.missingDurableConsent
        }
        guard durable.id == authorization.jobID,
              durable.projectID == staged.job.projectID,
              durable.capability == .image,
              durable.providerID == staged.job.providerID,
              durable.modelID == staged.job.modelID,
              durable.target == staged.job.target,
              durable.request == staged.job.request,
              durable.requestSHA256 == staged.job.requestSHA256,
              durable.estimatedCost == staged.job.estimatedCost else {
            throw Failure.jobChanged
        }
        // Jobs from prior app launches must be reconciled by the user, not sent
        // merely because they remain queued. The lifecycle actor tracks that.
        let requiringReview = await controller.jobsRequiringRecoveryReview()
        guard !requiringReview.contains(where: { $0.id == durable.id }) else {
            throw Failure.recoveryReviewRequired
        }
        let frozen = try OpenAIReferenceImageRequest.prepare(
            staged: staged, authorization: authorization,
            approval: approval, projectID: projectID, shot: shot,
            board: board, projectRoot: projectRoot)
        guard frozen.requestSHA256 == durable.requestSHA256,
              frozen.sourceImageSHA256 == authorization.approvedImageSHA256,
              SHA256.hash(data: frozen.body).map({ String(format: "%02x", $0) }).joined() == frozen.bodySHA256,
              frozen.endpoint.scheme == "https",
              frozen.endpoint.host == "api.openai.com" else {
            throw Failure.invalidPayload
        }
        return Ready(
            jobID: durable.id, endpoint: frozen.endpoint,
            body: frozen.body, bodySHA256: frozen.bodySHA256,
            consentedAt: durable.consentedAt!,
            requestSHA256: durable.requestSHA256)
    }
}
