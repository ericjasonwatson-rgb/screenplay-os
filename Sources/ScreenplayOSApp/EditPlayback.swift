import Foundation
import ScreenplayDomain

struct TimedEditClip: Identifiable {
    var clip: EditClip
    var start: Double
    var id: UUID { clip.id }
    var duration: Double { max(0.5, clip.timelineDurationSeconds.isFinite ? clip.timelineDurationSeconds : 0.5) }
}

struct TimedEditSegment: Identifiable {
    let id: UUID
    let sceneSpineID: String
    let label: String
    let start: Double
    let duration: Double
    let clip: EditClip?
    let estimate: SceneDurationEstimate?
}

extension ScreenplayViewModel {
    /// Derived timeline only: estimates never become persisted clips. Timing-guide exports use placeholders.
    var editTimeline: [TimedEditSegment] {
        if let editTimelineCache { return editTimelineCache }
        let estimates = showEditEstimates ? SceneDurationEstimate.byScene(in: elements) : [:]
        var cursor = 0.0
        var result: [TimedEditSegment] = []
        for beat in editorialBeats {
            // Authored boards/media retain their existing timing. Shot placeholders
            // can yield to a whole-scene estimate until timed material exists.
            let hasTimedMaterial = beat.editClips.contains { $0.sourceKind != .shotPlaceholder }
            if !hasTimedMaterial, let estimate = estimates[beat.sceneSpineID] {
                let duration = (estimate.minimumSeconds + estimate.maximumSeconds) / 2
                result.append(TimedEditSegment(id: beat.id, sceneSpineID: beat.sceneSpineID,
                    label: beat.title, start: cursor, duration: duration, clip: nil, estimate: estimate))
                cursor += duration
            } else {
                for clip in beat.editClips {
                    let duration = TimedEditClip(clip: clip, start: cursor).duration
                    result.append(TimedEditSegment(id: clip.id, sceneSpineID: beat.sceneSpineID,
                        label: clip.label, start: cursor, duration: duration, clip: clip, estimate: nil))
                    cursor += duration
                }
            }
        }
        editTimelineCache = result
        return result
    }
    var timedEditClips: [TimedEditClip] {
        editTimeline.compactMap { entry in entry.clip.map { TimedEditClip(clip: $0, start: entry.start) } }
    }
    var editDuration: Double {
        guard let last = editTimeline.last else { return 0 }
        return last.start + last.duration
    }
    var editTimelineHasEstimates: Bool { editTimeline.contains { $0.estimate != nil } }
    var untimedEditSceneCount: Int {
        let timed = Set(editTimeline.map(\.sceneSpineID))
        return editorialBeats.filter { !timed.contains($0.sceneSpineID) }.count
    }
    func pauseEditPlayback() { editIsPlaying = false }
    func toggleEditPlayback() {
        guard editDuration > 0 else { return }
        pauseBoardomatic()
        if editIsPlaying { pauseEditPlayback(); return }
        if editPlayheadSeconds >= editDuration { seekEdit(to: 0) }
        editIsPlaying = true
    }
    func advanceEditPlayback(by seconds: Double) {
        guard editIsPlaying else { return }
        seekEdit(to: editPlayheadSeconds + max(0, seconds), keepPlaying: true)
    }
    func seekEdit(to seconds: Double, keepPlaying: Bool = false) {
        if !keepPlaying { pauseEditPlayback() }
        let entries = editTimeline
        let duration = entries.last.map { $0.start + $0.duration } ?? 0
        editPlayheadSeconds = min(duration, max(0, seconds.isFinite ? seconds : 0))
        if editPlayheadSeconds >= duration { pauseEditPlayback() }
        guard let entry = entries.first(where: { editPlayheadSeconds < $0.start + $0.duration }) ?? entries.last else { return }
        if let beat = editorialBeats.first(where: { $0.sceneSpineID == entry.sceneSpineID }) {
            selectEditorialBeat(beat)
        }
        if let boardID = entry.clip?.boardFrameID, let board = boardFrames.first(where: { $0.id == boardID }) {
            selectBoardFrame(board)
        }
    }
}
