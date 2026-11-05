import CryptoKit
import Foundation
import ScreenplayDomain

/// Rebuilds an unselected Take from a previously paid, completed local result.
/// This path cannot contact a provider and does not mutate the screenplay.
enum ProductionImageCompletedResultRecovery {
    enum Failure: Error, Equatable {
        case missingCompletedJob
        case mismatchedSource
    }

    static func candidate(
        controller: GenerationJobController,
        jobID: UUID,
        approval: ProductionBoardApproval,
        shot: Shot,
        board: BoardFrame,
        documentURL: URL,
        recoveryRoot: URL,
        takeID: UUID
    ) async throws -> Take {
        let ledger = try await controller.snapshot().validated()
        guard ledger.projectID == approval.projectID,
              let job = ledger.jobs.first(where: { $0.id == jobID }),
              job.status == .succeeded, job.capability == .image,
              job.consentedAt != nil, job.submittedAt != nil,
              let completedAt = job.completedAt else {
            throw Failure.missingCompletedJob
        }
        try ProductionBoardApprovals.validate(
            approval, projectID: ledger.projectID, shot: shot, board: board)
        guard job.target.kind == .board, job.target.id == board.id,
              job.request.parameters["workflow"] == "production_image_from_approved_board",
              job.request.references.count == 1,
              let reference = job.request.references.first,
              reference.kind == "approved_board", reference.mediaType == "image/png",
              reference.id == board.selectedImageID,
              reference.sha256 == board.selectedImage?.sha256,
              job.target.sourceRevision == sha256(Data(job.request.prompt.utf8)),
              !board.imageVersions.contains(where: { $0.generationJobID == job.id }) else {
            throw Failure.mismatchedSource
        }
        let png = try ProductionImageResultVault.load(
            projectID: ledger.projectID, jobID: jobID, root: recoveryRoot)
        let stored = try BoardImageStorage.store(png, beside: documentURL)
        let provenance = Take.Provenance(
            source: .generationJob, generationJobID: job.id,
            providerID: job.providerID, modelID: job.modelID,
            prompt: job.request.prompt,
            promptSHA256: sha256(Data(job.request.prompt.utf8)),
            referenceAssetPaths: job.request.references.map(\.relativePath),
            consentRecordIDs: job.request.consentRecordIDs,
            generatedAt: completedAt,
            estimatedCost: job.estimatedCost, actualCost: job.actualCost)
        let result = Take(
            id: takeID, shotID: shot.id, boardFrameID: board.id,
            order: board.imageVersions.count, kind: .generatedImage,
            mediaURL: stored, sha256: sha256(png),
            durationSeconds: board.durationSeconds, status: .candidate,
            note: board.notes, provenance: provenance)
        _ = try TakeLedger(
            projectID: ledger.projectID,
            sourceRevision: BoardTakeMigration.sourceRevision([board]),
            takes: [result]).validated()
        return result
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
