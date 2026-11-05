import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Read-only media interchange manifest")
struct MediaInterchangeManifestTests {
    private func occurrence(
        id: UUID = UUID(), scene: UUID = UUID(), shot: UUID = UUID(),
        media: String? = "attachments/take.mov", start: Int = 0, duration: Int = 24
    ) -> MediaInterchangeManifest.Occurrence {
        .init(occurrenceID: id, sceneID: scene, shotID: shot, boardID: nil,
              mediaPath: media, startFrame: start, durationFrames: duration, note: "Keep this trim")
    }

    @Test func repeatedShotKeepsIndependentEditOccurrences() throws {
        let scene = UUID(), shot = UUID()
        let a = occurrence(scene: scene, shot: shot)
        let b = occurrence(scene: scene, shot: shot, start: 24)
        let manifest = try MediaInterchangeManifest.make([a, b], mediaExists: { _ in true })
        let decoded = try JSONDecoder().decode(
            MediaInterchangeManifest.Manifest.self, from: MediaInterchangeManifest.json(manifest))
        #expect(decoded.occurrences.count == 2)
        #expect(decoded.occurrences[0].shotID == decoded.occurrences[1].shotID)
        #expect(decoded.occurrences[0].occurrenceID != decoded.occurrences[1].occurrenceID)
        #expect(decoded.occurrences[1].startFrame == 24)
        #expect(decoded.occurrences[0].note == "Keep this trim")
    }

    @Test func missingMediaIsReportedWithoutDroppingReferences() throws {
        let item = occurrence()
        let result = try MediaInterchangeManifest.make([item], mediaExists: { _ in false })
        #expect(result.occurrences == [item])
        #expect(result.missingMedia == [.init(occurrenceID: item.occurrenceID, path: "attachments/take.mov")])
    }

    @Test func rejectsUnsafePaths() {
        for path in ["/private/film.mov", "../secret.mov", "assets/../../secret.mov",
                     "file:///private/film.mov", "C:/secret.mov", "assets//take.mov",
                     "assets/./take.mov", "assets\\take.mov"] {
            #expect(!MediaInterchangeManifest.safeRelativePath(path))
            #expect(throws: MediaInterchangeManifest.ValidationError.self) {
                try MediaInterchangeManifest.make([occurrence(media: path)], mediaExists: { _ in true })
            }
        }
        #expect(MediaInterchangeManifest.safeRelativePath("attachments/scene-1/take.mov"))
    }

    @Test func rejectsDuplicateIdentityAndInvalidTiming() {
        let a = occurrence()
        #expect(throws: MediaInterchangeManifest.ValidationError.self) {
            try MediaInterchangeManifest.make([a, a], mediaExists: { _ in true })
        }
        #expect(throws: MediaInterchangeManifest.ValidationError.self) {
            try MediaInterchangeManifest.make([occurrence(start: -1)], mediaExists: { _ in true })
        }
        #expect(throws: MediaInterchangeManifest.ValidationError.self) {
            try MediaInterchangeManifest.make([occurrence(duration: 0)], mediaExists: { _ in true })
        }
    }

    @Test func timelineBridgePreservesRealIDsAndRejectsMissingBindings() throws {
        let scene = UUID(), shot = UUID(), board = UUID()
        let first = TimedEditSegment(id: UUID(), sceneSpineID: "S001", label: "First",
                                     start: 0, duration: 1, clip: nil, estimate: nil)
        let second = TimedEditSegment(id: UUID(), sceneSpineID: "S001", label: "Repeat",
                                      start: 1, duration: 2, clip: nil, estimate: nil)
        let binding = MediaInterchangeManifest.SourceBinding(
            sceneID: scene, shotID: shot, boardID: board,
            mediaPath: "attachments/take.mov", note: "Director selected")
        let result = try MediaInterchangeManifest.fromTimeline(
            [first, second], bindings: [first.id: binding, second.id: binding],
            mediaExists: { _ in true })
        #expect(result.occurrences.map(\.occurrenceID) == [first.id, second.id])
        #expect(result.occurrences.map(\.shotID) == [shot, shot])
        #expect(result.occurrences.map(\.durationFrames) == [24, 48])
        #expect(result.occurrences.allSatisfy { $0.boardID == board && $0.note == "Director selected" })
        #expect(throws: MediaInterchangeManifest.TimelineError.self) {
            try MediaInterchangeManifest.fromTimeline([first, second],
                bindings: [first.id: binding], mediaExists: { _ in true })
        }
    }


    @Test func snapshotReadValidatesVersionAndMissingMedia() throws {
        let item = occurrence()
        let original = try MediaInterchangeManifest.make([item], mediaExists: { _ in false })
        let restored = try MediaInterchangeManifest.read(MediaInterchangeManifest.json(original))
        #expect(restored == original)
        let unsupported = MediaInterchangeManifest.Manifest(
            formatVersion: 2, occurrences: [item], missingMedia: [])
        #expect(throws: MediaInterchangeManifest.ImportError.self) {
            try MediaInterchangeManifest.read(MediaInterchangeManifest.json(unsupported))
        }
        let forged = MediaInterchangeManifest.Manifest(
            formatVersion: 1, occurrences: [item],
            missingMedia: [.init(occurrenceID: UUID(), path: "attachments/take.mov")])
        #expect(throws: MediaInterchangeManifest.ImportError.self) {
            try MediaInterchangeManifest.read(MediaInterchangeManifest.json(forged))
        }
    }

}
