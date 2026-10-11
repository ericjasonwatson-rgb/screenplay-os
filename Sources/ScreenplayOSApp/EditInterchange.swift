import Foundation
import ScreenplayDomain

/// A timing-guide export. No media links are invented from scene/board identifiers.
enum EditInterchange {
    enum Failure: LocalizedError {
        case empty, limits
        var errorDescription: String? {
            switch self {
            case .empty: return "The timeline is empty. Enable Estimates or add timed boards before exporting."
            case .limits: return "This timeline exceeds the export limits (999 events and less than 24 hours at 24 fps), or contains invalid timing."
            }
        }
    }
    struct Event {
        let segment: TimedEditSegment
        let start: Int
        let end: Int
    }
    static func events(_ segments: [TimedEditSegment]) throws -> [Event] {
        guard !segments.isEmpty else { throw Failure.empty }
        guard segments.count <= 999 else { throw Failure.limits }
        var cursor = 0
        return try segments.map { segment in
            let end = segment.start + segment.duration
            guard segment.start.isFinite, segment.duration.isFinite, segment.start >= 0,
                  segment.duration > 0, end.isFinite, end < 86400 else { throw Failure.limits }
            let startFrame = Int((segment.start * 24).rounded())
            let endFrame = Int((end * 24).rounded())
            guard startFrame == cursor, endFrame > startFrame else { throw Failure.limits }
            cursor = endFrame
            return Event(segment: segment, start: startFrame, end: endFrame)
        }
    }
    static func timecode(_ frames: Int) -> String {
        String(format: "%02d:%02d:%02d:%02d", frames / 86400, frames / 1440 % 60, frames / 24 % 60, frames % 24)
    }
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.map { $0.value >= 32 && $0.value != 127 ? Character($0) : Character(" ") })
    }
    static func xml(_ text: String) -> String {
        clean(text).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func label(_ segment: TimedEditSegment) -> String {
        "\(segment.estimate == nil ? "Placeholder" : "Estimated") · \(segment.sceneSpineID) · \(segment.label)"
    }
    static func edl(title: String, segments: [TimedEditSegment], audio: [EditAudioClip] = []) throws -> String {
        let entries = try events(segments)
        // CMX uses ASCII text. Unicode remains available in the FCPXML export.
        func ascii(_ text: String) -> String { String(clean(text).unicodeScalars.map { $0.isASCII ? Character($0) : Character("?") }) }
        var lines = ["TITLE: \(ascii(title))", "FCM: NON-DROP FRAME", "", "* SCREENPLAYOS TIMING GUIDE - 24 FPS - OFFLINE PLACEHOLDERS; NO MEDIA INCLUDED", ""]
        for (index, entry) in entries.enumerated() {
            lines.append(String(format: "%03d  P%07d V     C        %@ %@ %@ %@", index + 1, index + 1,
                                timecode(0), timecode(entry.end-entry.start), timecode(entry.start), timecode(entry.end)))
            lines.append("* FROM CLIP NAME: \(ascii(label(entry.segment)))")
            lines.append("* SCREENPLAYOS ID: \(entry.segment.id.uuidString)")
            lines.append("")
        }
        for (offset, clip) in audio.sorted(by: { ($0.timelineStartSeconds, $0.id.uuidString) < ($1.timelineStartSeconds, $1.id.uuidString) }).enumerated() {
            let sourceStart = Int((clip.sourceInSeconds * 24).rounded())
            let duration = Int((clip.durationSeconds * 24).rounded())
            let recordStart = Int((clip.timelineStartSeconds * 24).rounded())
            guard duration > 0, recordStart >= 0, recordStart + duration < 86_400 * 24 else { throw Failure.limits }
            lines.append(String(format: "%03d  A%07d A     C        %@ %@ %@ %@", entries.count + offset + 1, offset + 1,
                                timecode(sourceStart), timecode(sourceStart + duration), timecode(recordStart), timecode(recordStart + duration)))
            lines.append("* FROM CLIP NAME: \(ascii(clip.name))")
            lines.append("* SOURCE FILE: \(ascii(clip.mediaURL.path))")
            lines.append("* SCREENPLAYOS AUDIO LANE: \(clip.lane.rawValue)")
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }
    static func fcpxml(title: String, segments: [TimedEditSegment], audio: [EditAudioClip] = []) throws -> String {
        let entries = try events(segments)
        let gaps = entries.map { entry in
            "<gap name=\"\(xml(label(entry.segment)))\" offset=\"\(entry.start)/24s\" start=\"0s\" duration=\"\(entry.end-entry.start)/24s\"><note>ScreenplayOS timing placeholder; no media included. ID: \(entry.segment.id.uuidString)</note></gap>"
        }.joined(separator: "\n")
        let orderedAudio = audio.sorted { ($0.timelineStartSeconds, $0.id.uuidString) < ($1.timelineStartSeconds, $1.id.uuidString) }
        let assets = orderedAudio.enumerated().map { index, clip in
            "<asset id=\"a\(index + 1)\" name=\"\(xml(clip.name))\" src=\"\(xml(clip.mediaURL.absoluteString))\" start=\"0s\" duration=\"\(clip.sourceInSeconds + clip.durationSeconds)s\" hasAudio=\"1\" audioSources=\"1\"/>"
        }.joined(separator: "\n")
        let audioClips = orderedAudio.enumerated().map { index, clip in
            let lane = switch clip.lane { case .dialogue: -1; case .music: -2; case .effects: -3 }
            return "<asset-clip name=\"\(xml(clip.name))\" ref=\"a\(index + 1)\" lane=\"\(lane)\" offset=\"\(clip.timelineStartSeconds)s\" start=\"\(clip.sourceInSeconds)s\" duration=\"\(clip.durationSeconds)s\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
        <resources><format id="r1" frameDuration="1/24s" width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/>\(assets)</resources>
        <library><event name="ScreenplayOS"><project name="\(xml(title))">
        <sequence format="r1" duration="\(entries.last!.end)/24s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
        <spine>
        \(gaps)
        \(audioClips)
        </spine></sequence></project></event></library>
        </fcpxml>
        """
    }
}

extension ScreenplayViewModel {
    func editInterchangeText(for kind: ProductionExportKind) throws -> String {
        let audio = editAudioLedger?.clips ?? []
        if kind == .premiereEDL { return try EditInterchange.edl(title: title, segments: editTimeline, audio: audio) }
        return try EditInterchange.fcpxml(title: title, segments: editTimeline, audio: audio)
    }
}
