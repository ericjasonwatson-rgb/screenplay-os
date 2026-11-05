import Foundation
import ScreenplayDomain

/// The sole model-facing mapping from a validated, unselected production-image
/// Take to the existing canonical BoardFrame image versions. The caller must
/// first obtain that Take from ProductionImageResultPreparation's durable-job
/// entrypoint. No image selection, retiming, or edit reconstruction occurs.
enum ProductionImageCandidateAdoption {
    enum Failure: Error, Equatable {
        case boardNotFound
        case wrongTarget
        case invalidCandidate
        case duplicateID
        case duplicateMedia
    }

    static func appending(_ take: Take, to boards: [BoardFrame]) throws -> [BoardFrame] {
        guard let index = boards.firstIndex(where: { $0.id == take.boardFrameID }) else {
            throw Failure.boardNotFound
        }
        let board = boards[index]
        guard take.shotID == board.shotID,
              take.boardFrameID == board.id else { throw Failure.wrongTarget }
        guard take.kind == .generatedImage,
              take.status == .candidate,
              take.provenance.source == .generationJob,
              take.provenance.generationJobID != nil,
              take.provenance.generatedAt != nil,
              take.provenance.prompt != nil,
              take.provenance.modelID != nil,
              take.provenance.providerID != nil,
              take.durationSeconds == board.durationSeconds,
              take.inPointSeconds == 0,
              take.outPointSeconds == board.durationSeconds,
              take.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { throw Failure.invalidCandidate }

        guard !boards.contains(where: { b in b.imageVersions.contains(where: { $0.id == take.id }) }) else {
            throw Failure.duplicateID
        }
        // A separate generated Take with identical media is not useful, and
        // could obscure provenance for an existing version.
        guard !board.imageVersions.contains(where: { $0.sha256 == take.sha256 }) else {
            throw Failure.duplicateMedia
        }
        let version = BoardImageVersion(
            id: take.id, fileURL: take.mediaURL,
            sha256: take.sha256, prompt: take.provenance.prompt ?? "",
            model: take.provenance.modelID ?? "",
            providerID: take.provenance.providerID,
            generationJobID: take.provenance.generationJobID,
            generatedAt: take.provenance.generatedAt,
            estimatedCost: take.provenance.estimatedCost,
            actualCost: take.provenance.actualCost
        )
        var output = boards
        output[index].imageVersions.append(version)
        // Preserve the approved image and timing. Film-maker selection is
        // a separate existing undoable action: selectBoardImage(_:for:).
        return output
    }
}
