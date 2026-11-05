import Foundation

/// Compares an externally edited interchange snapshot to a known baseline.
/// No project mutation: changes remain reviewable proposals.
enum MediaEditReview {
    struct Change: Equatable {
        enum Kind: Equatable {
            case reordered(from: Int, to: Int)
            case timing(fromStart: Int, fromDuration: Int, toStart: Int, toDuration: Int)
            case media(from: String?, to: String?)
            case note(from: String, to: String)
        }
        let occurrenceID: UUID
        let kind: Kind
    }

    struct Proposal: Equatable {
        let changes: [Change]
        let unchangedCount: Int
    }

    enum ReviewError: Error, Equatable {
        case missingOccurrence(UUID)
        case addedOccurrence(UUID)
        case sourceIdentityChanged(UUID)
        case sourceTakeChanged(UUID)
    }

    /// An external edit may change order, timing, media and notes, but not canonical identities.
    /// Reject additions/deletions until an explicit mapping and adoption contract exists.
    static func compare(baseline: MediaInterchangeManifest.Manifest,
                        edited: MediaInterchangeManifest.Manifest) throws -> Proposal {
        let old = try MediaInterchangeManifest.read(MediaInterchangeManifest.json(baseline))
        let new = try MediaInterchangeManifest.read(MediaInterchangeManifest.json(edited))
        let oldByID = Dictionary(uniqueKeysWithValues: old.occurrences.enumerated().map { ($0.element.occurrenceID, ($0.offset, $0.element)) })
        let newByID = Dictionary(uniqueKeysWithValues: new.occurrences.enumerated().map { ($0.element.occurrenceID, ($0.offset, $0.element)) })
        for item in old.occurrences where newByID[item.occurrenceID] == nil {
            throw ReviewError.missingOccurrence(item.occurrenceID)
        }
        for item in new.occurrences where oldByID[item.occurrenceID] == nil {
            throw ReviewError.addedOccurrence(item.occurrenceID)
        }

        var changes: [Change] = []
        var unchanged = 0
        for (newIndex, item) in new.occurrences.enumerated() {
            guard let (oldIndex, previous) = oldByID[item.occurrenceID] else {
                throw ReviewError.addedOccurrence(item.occurrenceID)
            }
            guard item.sceneID == previous.sceneID, item.shotID == previous.shotID,
                  item.boardID == previous.boardID else {
                throw ReviewError.sourceIdentityChanged(item.occurrenceID)
            }
            // A new video or alternate image is a reviewable media substitution,
            // not permission to silently rewrite the original Take's identity
            // or historical generation provenance.
            guard item.takeID == previous.takeID,
                  item.generationJobID == previous.generationJobID,
                  item.promptSHA256 == previous.promptSHA256,
                  item.mediaSHA256 == previous.mediaSHA256 else {
                throw ReviewError.sourceTakeChanged(item.occurrenceID)
            }
            let countBefore = changes.count
            if oldIndex != newIndex {
                changes.append(.init(occurrenceID: item.occurrenceID,
                                     kind: .reordered(from: oldIndex, to: newIndex)))
            }
            if previous.startFrame != item.startFrame || previous.durationFrames != item.durationFrames {
                changes.append(.init(occurrenceID: item.occurrenceID,
                                     kind: .timing(fromStart: previous.startFrame,
                                                   fromDuration: previous.durationFrames,
                                                   toStart: item.startFrame, toDuration: item.durationFrames)))
            }
            if previous.mediaPath != item.mediaPath {
                changes.append(.init(occurrenceID: item.occurrenceID,
                                     kind: .media(from: previous.mediaPath, to: item.mediaPath)))
            }
            if previous.note != item.note {
                changes.append(.init(occurrenceID: item.occurrenceID,
                                     kind: .note(from: previous.note, to: item.note)))
            }
            if changes.count == countBefore { unchanged += 1 }
        }
        return Proposal(changes: changes, unchangedCount: unchanged)
    }
}
