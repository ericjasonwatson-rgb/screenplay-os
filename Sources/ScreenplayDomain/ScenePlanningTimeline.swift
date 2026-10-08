import Foundation

/// Derived planning coordinates. Never written back into clip or screenplay timing.
public struct ScenePlanningTimeline {
    public struct Entry: Identifiable {
        public let id: UUID
        public let sceneSpineID: String
        public let title: String
        public let minimumSeconds: Double?
        public let maximumSeconds: Double?
        public let midpointStart: Double?
        public let usesMedia: Bool
        public var midpointSeconds: Double? {
            guard let minimumSeconds, let maximumSeconds else { return nil }
            return minimumSeconds / 2 + maximumSeconds / 2
        }
    }
    public let entries: [Entry]
    public let minimumSeconds: Double
    public let maximumSeconds: Double
    public var untimedCount: Int { entries.filter { $0.midpointSeconds == nil }.count }
    public var hasEstimates: Bool { entries.contains { !$0.usesMedia && $0.midpointSeconds != nil } }

    public init(beats: [EditorialBeat], estimates: [String: SceneDurationEstimate]) {
        var result: [Entry] = []
        var minimum = 0.0, maximum = 0.0
        var start: Double? = 0
        // Caller supplies editorial order, which can differ from screenplay order.
        for beat in beats {
            let media = Self.mediaDuration(for: beat)
            let estimate = estimates[beat.sceneSpineID]
            let low = media ?? estimate?.minimumSeconds
            let high = media ?? estimate?.maximumSeconds
            result.append(Entry(id: beat.id, sceneSpineID: beat.sceneSpineID, title: beat.title,
                                minimumSeconds: low, maximumSeconds: high,
                                midpointStart: start, usesMedia: media != nil))
            if let low, let high {
                minimum += low
                maximum += high
                start = start.map { $0 + low / 2 + high / 2 }
            } else { start = nil }
        }
        entries = result
        minimumSeconds = minimum
        maximumSeconds = maximum
    }

    /// Board durations are authored planning timing. Placeholder and omitted clips
    /// contribute no playback time; media timing requires a conformed status.
    public static func playableClips(in beat: EditorialBeat) -> [EditClip] {
        beat.editClips.filter {
            guard $0.timelineDurationSeconds.isFinite, $0.timelineDurationSeconds > 0,
                  $0.status != .omitted, $0.status != .placeholder else { return false }
            switch $0.sourceKind {
            case .shotPlaceholder: return false
            case .boardFrame: return true
            case .productionMedia, .generatedVideo:
                return [.assembled, .locked, .replaced].contains($0.status)
            }
        }
    }

    /// Current-cut timing is available only when every clip is usable media.
    /// Boards, placeholders, mixed and omitted clips do not confirm scene runtime.
    public static func mediaDuration(for beat: EditorialBeat) -> Double? {
        guard !beat.editClips.isEmpty, beat.editClips.allSatisfy({
            $0.timelineDurationSeconds.isFinite && $0.timelineDurationSeconds > 0 &&
            ($0.sourceKind == .productionMedia || $0.sourceKind == .generatedVideo) &&
            ($0.status == .assembled || $0.status == .locked || $0.status == .replaced)
        }) else { return nil }
        let total = beat.editClips.reduce(0) { $0 + $1.timelineDurationSeconds }
        return total.isFinite ? total : nil
    }
}
