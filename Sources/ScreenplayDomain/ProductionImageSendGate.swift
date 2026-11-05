import Foundation

/// A second, explicit consent boundary for a production image. This proof
/// cannot be created from storyboard approval alone. No network operation
/// takes place here and no job is advanced by this component.
public struct ProductionImageSendAuthorization: Equatable, Sendable {
    public let jobID: UUID
    public let requestSHA256: String
    public let approvedImageSHA256: String
    public let approvedBoardRevisionSHA256: String
    public let consentedAt: Date
}

public enum ProductionImageSendGateError: Error, Equatable {
    case notApprovedForSend
    case changedRequest
    case staleConsent
}

/// A caller may present a real Send button only once a production-image adapter
/// documents exact image input support, captures consent for its frozen payload,
/// and checks this proof immediately before dispatch. This type never sends.
public enum ProductionImageSendGate {
    public static func authorize(
        staged: ApprovedProductionImageReview,
        consentPreview: GenerationConsentPreview,
        explicitSendApproval: Bool,
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL,
        providerAcceptsReferenceImages: Bool,
        at date: Date
    ) throws -> ProductionImageSendAuthorization {
        guard explicitSendApproval else { throw ProductionImageSendGateError.notApprovedForSend }
        guard consentPreview.jobID == staged.job.id,
              consentPreview.projectID == projectID,
              consentPreview.capability == .image,
              consentPreview.providerID == staged.job.providerID,
              consentPreview.modelID == staged.job.modelID,
              consentPreview.target == staged.job.target,
              consentPreview.request == staged.job.request,
              consentPreview.requestSHA256 == staged.job.requestSHA256,
              consentPreview.estimatedCost == staged.job.estimatedCost else {
            throw ProductionImageSendGateError.changedRequest
        }
        try ApprovedProductionImageFlow.revalidate(
            staged, approval: approval, projectID: projectID, shot: shot,
            board: board, projectRoot: projectRoot,
            providerAcceptsReferenceImages: providerAcceptsReferenceImages)
        return ProductionImageSendAuthorization(
            jobID: staged.job.id,
            requestSHA256: staged.job.requestSHA256,
            approvedImageSHA256: staged.reference.imageSHA256,
            approvedBoardRevisionSHA256: approval.boardRevisionSHA256,
            consentedAt: date
        )
    }

    public static func revalidate(
        _ authorization: ProductionImageSendAuthorization,
        staged: ApprovedProductionImageReview,
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL,
        providerAcceptsReferenceImages: Bool
    ) throws {
        guard authorization.jobID == staged.job.id,
              authorization.requestSHA256 == staged.job.requestSHA256,
              authorization.approvedImageSHA256 == staged.reference.imageSHA256,
              authorization.approvedBoardRevisionSHA256 == approval.boardRevisionSHA256
        else { throw ProductionImageSendGateError.staleConsent }
        try ApprovedProductionImageFlow.revalidate(
            staged, approval: approval, projectID: projectID, shot: shot,
            board: board, projectRoot: projectRoot,
            providerAcceptsReferenceImages: providerAcceptsReferenceImages)
    }
}
