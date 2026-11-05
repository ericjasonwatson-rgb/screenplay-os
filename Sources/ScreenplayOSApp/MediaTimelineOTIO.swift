import Foundation

/// A deliberately narrow OTIO JSON export for review in external editors.
/// No network IO or project mutation. Import and NLE compatibility remain unverified.
enum MediaTimelineOTIO {
    enum ExportError: Error, Equatable {
        case invalidRate
        case nonContiguousTimeline
        case missingAsset(UUID)
    }

    static func export(_ manifest: MediaInterchangeManifest.Manifest,
                       projectName: String,
                       framesPerSecond: Int = 24,
                       requireMedia: Bool = false) throws -> Data {
        guard framesPerSecond > 0 && framesPerSecond <= 120 else { throw ExportError.invalidRate }
        let checked = try MediaInterchangeManifest.read(MediaInterchangeManifest.json(manifest))
        var cursor = 0
        for item in checked.occurrences {
            guard item.startFrame == cursor else { throw ExportError.nonContiguousTimeline }
            let (next, overflow) = cursor.addingReportingOverflow(item.durationFrames)
            guard !overflow else { throw ExportError.nonContiguousTimeline }
            cursor = next
        }
        let missing = Set(checked.missingMedia.map(\.occurrenceID))
        if requireMedia, let first = checked.occurrences.first(where: { $0.mediaPath == nil || missing.contains($0.occurrenceID) }) {
            throw ExportError.missingAsset(first.occurrenceID)
        }

        func time(_ value: Int) -> [String: Any] {
            ["OTIO_SCHEMA": "RationalTime.1", "value": value, "rate": framesPerSecond]
        }
        func range(_ start: Int, _ duration: Int) -> [String: Any] {
            ["OTIO_SCHEMA": "TimeRange.1", "start_time": time(start), "duration": time(duration)]
        }
        let clips: [[String: Any]] = checked.occurrences.map { item in
            let reference: [String: Any]
            if let path = item.mediaPath, !missing.contains(item.occurrenceID) {
                // Relative references are intentional: no private machine paths in exported JSON.
                reference = ["OTIO_SCHEMA": "ExternalReference.1",
                             "target_url": path,
                             "available_range": range(0, item.durationFrames)]
            } else {
                reference = ["OTIO_SCHEMA": "MissingReference.1"]
            }
            return [
                "OTIO_SCHEMA": "Clip.2",
                "name": item.occurrenceID.uuidString,
                "source_range": range(0, item.durationFrames),
                "media_reference": reference,
                "metadata": ["screenplayos": [
                    "occurrence_id": item.occurrenceID.uuidString,
                    "scene_id": item.sceneID.uuidString,
                    "shot_id": item.shotID.uuidString,
                    "board_id": item.boardID?.uuidString as Any? ?? NSNull(),
                    "timeline_start_frame": item.startFrame,
                    "note": item.note,
                    "take_id": item.takeID?.uuidString as Any? ?? NSNull(),
                    "generation_job_id": item.generationJobID?.uuidString as Any? ?? NSNull(),
                    "media_sha256": item.mediaSHA256 as Any? ?? NSNull(),
                    "prompt_sha256": item.promptSHA256 as Any? ?? NSNull()
                ]]
            ]
        }
        let track: [String: Any] = [
            "OTIO_SCHEMA": "Track.1", "name": "Picture", "kind": "Video",
            "children": clips
        ]
        let timeline: [String: Any] = [
            "OTIO_SCHEMA": "Timeline.1", "name": projectName,
            "tracks": ["OTIO_SCHEMA": "Stack.1", "children": [track]]
        ]
        return try JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted, .sortedKeys])
    }
}
