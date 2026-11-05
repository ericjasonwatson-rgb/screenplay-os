import Foundation

/// The shared, local-only bridge from a *persisted* board approval to an exact
/// reference-image review. It cannot grant consent or invoke an image provider.
public struct ApprovedProductionImageReview: Sendable {
    public let approvalID: UUID
    public let brief: ProductionImageBrief
    public let job: GenerationJobRecord
    public let reference: ProductionImageReferenceReview
}

public enum ApprovedProductionImageFlow {
    /// A verified, reference-capable adapter must supply capability=true.
    /// No provider is contacted and no job status is advanced by this function.
    public static func prepare(
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        instruction: String,
        style: String,
        boardRelativePath: String,
        projectRoot: URL,
        providerID: String,
        modelID: String,
        providerAcceptsReferenceImages: Bool,
        jobID: UUID,
        at date: Date
    ) throws -> ApprovedProductionImageReview {
        try ProductionBoardApprovals.validate(
            approval, projectID: projectID, shot: shot, board: board)
        let brief = try ProductionImagePlanning.prepare(
            shot: shot, board: board, approvedBoardIDs: [approval.boardID],
            directingInstruction: instruction, styleInstruction: style)
        let job = try ProductionImageJobPlanning.awaitingConsent(
            brief: brief, shot: shot, board: board,
            approvedBoardIDs: [approval.boardID],
            projectID: projectID, jobID: jobID, providerID: providerID,
            modelID: modelID, boardRelativePath: boardRelativePath,
            createdAt: date)
        let reference = try ProductionImageReferencePreview.prepare(
            job: job, projectRoot: projectRoot,
            providerAcceptsReferenceImages: providerAcceptsReferenceImages)
        guard reference.jobID == job.id,
              reference.requestSHA256 == job.requestSHA256,
              reference.imageSHA256 == brief.selectedBoardImageSHA256 else {
            throw ProductionImageReferenceReviewError.referenceChanged
        }
        return ApprovedProductionImageReview(
            approvalID: approval.id, brief: brief, job: job, reference: reference)
    }

    /// Guard for any later Send action. Changes to the board, stored approval
    /// or request invalidate consent; none of these checks authorize egress.
    public static func revalidate(
        _ staged: ApprovedProductionImageReview,
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL,
        providerAcceptsReferenceImages: Bool
    ) throws {
        guard approval.id == staged.approvalID,
              staged.job.projectID == projectID,
              staged.job.requestSHA256 == staged.reference.requestSHA256,
              staged.job.target.id == board.id else {
            throw ProductionBoardApprovalError.changedSource
        }
        try ProductionBoardApprovals.validate(
            approval, projectID: projectID, shot: shot, board: board)
        try ProductionImagePlanning.validateCurrent(
            staged.brief, shot: shot, board: board,
            approvedBoardIDs: [approval.boardID])
        let refreshed = try ProductionImageReferencePreview.prepare(
            job: staged.job, projectRoot: projectRoot,
            providerAcceptsReferenceImages: providerAcceptsReferenceImages)
        guard refreshed.imageBytes == staged.reference.imageBytes,
              refreshed.requestSHA256 == staged.reference.requestSHA256 else {
            throw ProductionImageReferenceReviewError.referenceChanged
        }
    }
}
