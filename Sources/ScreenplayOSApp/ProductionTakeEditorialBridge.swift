import Foundation
import ScreenplayDomain

/// Explicit, read-only handoff of a generated Take to one occurrence of an
/// external editorial timeline. No canonical mutation, upload, selection,
/// or assumed FilmCraft/OTIO importer compatibility.
enum ProductionTakeEditorialBridge {
    enum Failure: Error, Equatable {
        case wrongShot
        case wrongBoard
        case invalidTake
        case unsafeMedia
        case invalidTiming
    }

    static func occurrence(
        id: UUID,
        sceneID: UUID,
        shotID: UUID,
        boardID: UUID,
        take: Take,
        relativeMediaPath: String,
        startFrame: Int,
        durationFrames: Int,
        note: String
    ) throws -> MediaInterchangeManifest.Occurrence {
        guard take.shotID == shotID else { throw Failure.wrongShot }
        guard take.boardFrameID == boardID else { throw Failure.wrongBoard }
        guard take.kind == .generatedImage || take.kind == .generatedVideo,
              take.status != .rejected,
              take.provenance.source == .generationJob,
              let generationJobID = take.provenance.generationJobID,
              take.provenance.promptSHA256 != nil,
              take.sha256.utf8.count == 64 else {
            throw Failure.invalidTake
        }
        guard MediaInterchangeManifest.safeRelativePath(relativeMediaPath) else {
            throw Failure.unsafeMedia
        }
        guard startFrame >= 0, durationFrames > 0,
              startFrame <= Int.max - durationFrames else {
            throw Failure.invalidTiming
        }
        return MediaInterchangeManifest.Occurrence(
            occurrenceID: id, sceneID: sceneID, shotID: shotID,
            boardID: boardID, mediaPath: relativeMediaPath,
            startFrame: startFrame, durationFrames: durationFrames, note: note,
            takeID: take.id, generationJobID: generationJobID,
            mediaSHA256: take.sha256,
            promptSHA256: take.provenance.promptSHA256
        )
    }

    /// Compare two local snapshots; never apply edits or accept identity drift.
    static func compareExternalProposal(
        baseline: MediaInterchangeManifest.Manifest,
        edited: MediaInterchangeManifest.Manifest
    ) throws -> MediaEditReview.Proposal {
        try MediaEditReview.compare(baseline: baseline, edited: edited)
    }
}
