import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Draft OTIO interchange")
struct MediaTimelineOTIOTests {
    private func occurrence(start: Int, media: String? = "attachments/take.mov") -> MediaInterchangeManifest.Occurrence {
        .init(occurrenceID: UUID(), sceneID: UUID(), shotID: UUID(),
              boardID: nil, mediaPath: media, startFrame: start,
              durationFrames: 24, note: "Director approved")
    }

    @Test func exportsClipMetadataAndRelativeMediaReferences() throws {
        let a = occurrence(start: 0)
        let b = occurrence(start: 24)
        let manifest = try MediaInterchangeManifest.make([a, b], mediaExists: { _ in true })
        let data = try MediaTimelineOTIO.export(manifest, projectName: "Defenders")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["OTIO_SCHEMA"] as? String == "Timeline.1")
        let stack = try #require(json["tracks"] as? [String: Any])
        let tracks = try #require(stack["children"] as? [[String: Any]])
        let clips = try #require(tracks.first?["children"] as? [[String: Any]])
        #expect(clips.count == 2)
        let metadata = try #require(clips.first?["metadata"] as? [String: Any])
        let ids = try #require(metadata["screenplayos"] as? [String: Any])
        #expect(ids["occurrence_id"] as? String == a.occurrenceID.uuidString)
        #expect(ids["shot_id"] as? String == a.shotID.uuidString)
        let ref = try #require(clips.first?["media_reference"] as? [String: Any])
        #expect(ref["target_url"] as? String == "attachments/take.mov")
    }

    @Test func missingMediaBecomesPlaceholderAndStrictModeRejects() throws {
        let a = occurrence(start: 0)
        let manifest = try MediaInterchangeManifest.make([a], mediaExists: { _ in false })
        let data = try MediaTimelineOTIO.export(manifest, projectName: "Offline")
        #expect(String(decoding: data, as: UTF8.self).contains("MissingReference.1"))
        #expect(throws: MediaTimelineOTIO.ExportError.self) {
            try MediaTimelineOTIO.export(manifest, projectName: "Offline", requireMedia: true)
        }
    }

    @Test func refusesGappedTimelinesWithoutSilentlyRetiming() throws {
        let manifest = try MediaInterchangeManifest.make(
            [occurrence(start: 0), occurrence(start: 48)], mediaExists: { _ in true })
        #expect(throws: MediaTimelineOTIO.ExportError.self) {
            try MediaTimelineOTIO.export(manifest, projectName: "Gapped")
        }
    }
}
