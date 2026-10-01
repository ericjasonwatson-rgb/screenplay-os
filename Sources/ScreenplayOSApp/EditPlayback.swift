import Foundation
import ScreenplayDomain

struct TimedEditClip: Identifiable {
    var clip: EditClip
    var start: Double
    var id: UUID { clip.id }
    var duration: Double { max(0.5, clip.timelineDurationSeconds.isFinite ? clip.timelineDurationSeconds : 0.5) }
}

extension ScreenplayViewModel {
    var timedEditClips: [TimedEditClip] {
        var cursor = 0.0
        return editorialBeats.flatMap(\.editClips).map { clip in
            let entry = TimedEditClip(clip: clip, start: cursor)
            cursor += entry.duration
            return entry
        }
    }
    var editDuration: Double {
        guard let last = timedEditClips.last else { return 0 }
        return last.start + last.duration
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
        let clips = timedEditClips
        let duration = clips.last.map { $0.start + $0.duration } ?? 0
        editPlayheadSeconds = min(duration, max(0, seconds.isFinite ? seconds : 0))
        if editPlayheadSeconds >= duration { pauseEditPlayback() }
        guard let entry = clips.first(where: { editPlayheadSeconds < $0.start + $0.duration }) ?? clips.last else { return }
        if let beat = editorialBeats.first(where: { $0.sceneSpineID == entry.clip.sceneSpineID }) {
            selectEditorialBeat(beat)
        }
        if let boardID = entry.clip.boardFrameID, let board = boardFrames.first(where: { $0.id == boardID }) {
            selectBoardFrame(board)
        }
    }
}
