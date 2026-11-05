import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("External edit review proposals")
struct MediaEditReviewTests {
    private func occurrence(_ id: UUID, scene: UUID, shot: UUID, start: Int,
                            media: String? = "attachments/board.png",
                            note: String = "Original") -> MediaInterchangeManifest.Occurrence {
        .init(occurrenceID: id, sceneID: scene, shotID: shot, boardID: nil,
              mediaPath: media, startFrame: start, durationFrames: 24, note: note)
    }

    @Test func unchangedSnapshotCreatesNoChanges() throws {
        let item = occurrence(UUID(), scene: UUID(), shot: UUID(), start: 0)
        let snapshot = try MediaInterchangeManifest.make([item], mediaExists: { _ in true })
        let review = try MediaEditReview.compare(baseline: snapshot, edited: snapshot)
        #expect(review.changes.isEmpty)
        #expect(review.unchangedCount == 1)
    }

    @Test func reorderAndMediaReplacementBecomeProposals() throws {
        let scene = UUID(), shot = UUID()
        let aID = UUID(), bID = UUID()
        let a = occurrence(aID, scene: scene, shot: shot, start: 0)
        let b = occurrence(bID, scene: scene, shot: shot, start: 24)
        let editedA = occurrence(aID, scene: scene, shot: shot, start: 24,
                                 media: "attachments/take.mov", note: "Selected")
        let editedB = occurrence(bID, scene: scene, shot: shot, start: 0)
        let old = try MediaInterchangeManifest.make([a, b], mediaExists: { _ in true })
        let new = try MediaInterchangeManifest.make([editedB, editedA], mediaExists: { _ in true })
        let review = try MediaEditReview.compare(baseline: old, edited: new)
        #expect(review.changes.contains { $0.occurrenceID == aID && $0.kind == .media(from: "attachments/board.png", to: "attachments/take.mov") })
        #expect(review.changes.contains { $0.occurrenceID == aID && $0.kind == .reordered(from: 0, to: 1) })
        #expect(review.changes.contains { $0.occurrenceID == aID && $0.kind == .timing(fromStart: 0, fromDuration: 24, toStart: 24, toDuration: 24) })
        #expect(review.changes.contains { $0.occurrenceID == aID && $0.kind == .note(from: "Original", to: "Selected") })
        #expect(old.occurrences == [a, b]) // review does not mutate source
    }

    @Test func changedSourceIdentityAndUnmappedClipsFailClosed() throws {
        let id = UUID(), scene = UUID(), shot = UUID()
        let old = try MediaInterchangeManifest.make(
            [occurrence(id, scene: scene, shot: shot, start: 0)], mediaExists: { _ in true })
        let altered = try MediaInterchangeManifest.make(
            [occurrence(id, scene: scene, shot: UUID(), start: 0)], mediaExists: { _ in true })
        #expect(throws: MediaEditReview.ReviewError.self) {
            try MediaEditReview.compare(baseline: old, edited: altered)
        }
        let added = try MediaInterchangeManifest.make(
            [occurrence(UUID(), scene: scene, shot: shot, start: 0)], mediaExists: { _ in true })
        #expect(throws: MediaEditReview.ReviewError.self) {
            try MediaEditReview.compare(baseline: old, edited: added)
        }
    }
}
