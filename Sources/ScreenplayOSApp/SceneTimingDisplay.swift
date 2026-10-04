import Foundation
import ScreenplayDomain

/// Board/placeholder timing is not evidence of a scene's actual runtime.
struct SceneTimingDisplay {
    let timing: String
    let estimate: String?
    static let assumptions = "Script estimate: dialogue at 120–180 words/minute; action prose at 60–120 words/minute, rounded to 5 seconds. Staging, pauses and action can fall outside this range. Estimates never change clip timing. Media edit timing describes the current cut, not scene completeness."

    init(beat: EditorialBeat, scriptEstimate: SceneDurationEstimate?, showEstimate: Bool) {
        let clips = beat.editClips
        let valid = !clips.isEmpty && clips.allSatisfy { $0.timelineDurationSeconds.isFinite && $0.timelineDurationSeconds > 0 }
        let media = ScenePlanningTimeline.mediaDuration(for: beat) != nil
        if valid {
            let kind = media ? "Media edit" : clips.allSatisfy { $0.sourceKind == .boardFrame } ? "Boards" : "Planned edit"
            timing = String(format: "%@: %.1fs · %d %@", kind, clips.reduce(0) { $0 + $1.timelineDurationSeconds }, clips.count, clips.count == 1 ? "clip" : "clips")
                + (clips.contains { $0.status == .omitted } ? " · includes omitted" : "")
        } else { timing = "No timed clips" }
        if showEstimate && !media {
            estimate = scriptEstimate.map { "Est. \(Self.clock($0.minimumSeconds))–\(Self.clock($0.maximumSeconds))" } ?? "Est. unavailable"
        } else { estimate = nil }
    }
    private static func clock(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
