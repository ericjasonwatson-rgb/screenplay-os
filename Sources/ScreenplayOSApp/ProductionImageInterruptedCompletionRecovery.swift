import CryptoKit
import Foundation
import ScreenplayDomain

/// Explicit, network-free reconciliation for a provider output that was saved
/// before its running job could be durably marked succeeded (e.g. disk failure).
/// Must be invoked by the filmmaker, never automatically on app launch.
enum ProductionImageInterruptedCompletionRecovery {
    enum Failure: Error, Equatable {
        case notSubmitted
        case wrongRequest
        case missingPreservedOutput
    }

    /// A successful return changes only the durable job state to succeeded.
    /// It does not select or insert a Take. The caller may then invoke the
    /// existing completed-result recovery to create an unselected candidate.
    static func completeFromVault(
        controller: GenerationJobController,
        jobID: UUID,
        approval: ProductionBoardApproval,
        shot: Shot,
        board: BoardFrame,
        recoveryRoot: URL,
        at date: Date
    ) async throws {
        let ledger = try await controller.snapshot().validated()
        guard ledger.projectID == approval.projectID,
              let job = ledger.jobs.first(where: { $0.id == jobID }),
              job.status == .running,
              job.capability == .image,
              job.consentedAt != nil,
              job.submittedAt != nil,
              job.completedAt == nil else {
            throw Failure.notSubmitted
        }
        try ProductionBoardApprovals.validate(
            approval, projectID: ledger.projectID, shot: shot, board: board)
        guard job.target.kind == .board,
              job.target.id == board.id,
              job.request.parameters["workflow"] == "production_image_from_approved_board",
              job.request.references.count == 1,
              let reference = job.request.references.first,
              reference.kind == "approved_board",
              reference.mediaType == "image/png",
              reference.id == board.selectedImageID,
              reference.sha256 == board.selectedImage?.sha256,
              job.target.sourceRevision == sha256(Data(job.request.prompt.utf8)),
              !board.imageVersions.contains(where: { $0.generationJobID == job.id }) else {
            throw Failure.wrongRequest
        }
        // A provider response must already have been validated and preserved
        // in this job's exclusive private recovery file. Never call transport.
        guard (try? ProductionImageResultVault.load(
            projectID: ledger.projectID, jobID: job.id, root: recoveryRoot)) != nil else {
            throw Failure.missingPreservedOutput
        }
        try await controller.markSucceeded(jobID: job.id, at: date)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
