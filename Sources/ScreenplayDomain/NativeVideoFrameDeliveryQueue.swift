import Foundation

/// Bounded, identity-aware policy for moving already decoded frames from a
/// source-PTS decoder to a monotonic 24 fps presentation clock. This type never
/// decodes, reads files, or starts playback by itself.
public struct NativeVideoFrameDeliveryQueue: Sendable {
    public struct Request: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sessionID: UUID
        public let timelineFrame: Int
        public let localFrame: Int
        public let clip: NativeAssemblyClip

        public var occurrenceID: UUID { clip.id }
        public var takeID: UUID { clip.takeID }
        public var mediaSHA256: String { clip.mediaSHA256 }
    }

    public struct Presentation: Equatable, Sendable {
        /// Frame requested by the clock; may exceed deliveredFrame only when
        /// a verified frame is held briefly within the SAME occurrence.
        public let requestedFrame: Int
        public let deliveredFrame: Int
        public let occurrenceID: UUID
        public let takeID: UUID
        public let mediaSHA256: String
        public let pngData: Data
        public var isHeld: Bool { requestedFrame != deliveredFrame }
    }

    private struct Ready: Sendable {
        let request: Request
        let pngData: Data
    }

    public enum Failure: Error, Equatable {
        case invalidLimits
    }

    public let project: NativeAssemblyProject
    public let maximumInFlight: Int
    public let maximumReady: Int
    public let maximumReadyBytes: Int
    public let lookaheadFrames: Int
    public let maximumHoldFrames: Int

    public private(set) var sessionID = UUID()
    private var inFlight: [UUID: Request] = [:]
    private var ready: [Int: Ready] = [:]
    public private(set) var readyBytes = 0
    public private(set) var rejectedCompletions = 0
    public private(set) var lateCompletions = 0
    public private(set) var skippedFrames = 0

    public var inFlightCount: Int { inFlight.count }
    public var readyCount: Int { ready.count }
    public var inFlightRequestIDs: Set<UUID> { Set(inFlight.keys) }

    public init(project: NativeAssemblyProject, maximumInFlight: Int = 2,
                maximumReady: Int = 4, maximumReadyBytes: Int = 16 * 1024 * 1024,
                lookaheadFrames: Int = 3, maximumHoldFrames: Int = 1) throws {
        self.project = try project.validated()
        guard (1...4).contains(maximumInFlight),
              (1...16).contains(maximumReady),
              (1...32 * 1024 * 1024).contains(maximumReadyBytes),
              (0...12).contains(lookaheadFrames),
              (0...2).contains(maximumHoldFrames) else {
            throw Failure.invalidLimits
        }
        self.maximumInFlight = maximumInFlight
        self.maximumReady = maximumReady
        self.maximumReadyBytes = maximumReadyBytes
        self.lookaheadFrames = lookaheadFrames
        self.maximumHoldFrames = maximumHoldFrames
    }

    /// Schedules only currently needed video frames, most urgent first.
    /// Still-image clips do not produce requests; they are not passed to the
    /// video decoder and cannot be fabricated by this queue.
    public mutating func plan(at timelineFrame: Int) -> [Request] {
        guard (0..<project.totalFrames).contains(timelineFrame) else {
            retire(before: project.totalFrames)
            return []
        }
        retire(before: timelineFrame)
        var new: [Request] = []
        let end = min(project.totalFrames - 1, timelineFrame + lookaheadFrames)
        for frame in timelineFrame...end {
            guard inFlight.count < maximumInFlight,
                  let (clip, localFrame) = location(at: frame),
                  clip.mediaKind == .video,
                  ready[frame] == nil,
                  !inFlight.values.contains(where: { $0.timelineFrame == frame }) else {
                continue
            }
            let request = Request(id: UUID(), sessionID: sessionID,
                                  timelineFrame: frame, localFrame: localFrame, clip: clip)
            inFlight[request.id] = request
            new.append(request)
        }
        return new
    }

    /// Decoding and media verification happen outside this value type.
    /// Completion must match the original request token, session, occurrence,
    /// Take and digest exactly. Late completions are dropped, never displayed.
    @discardableResult
    public mutating func accept(_ pngData: Data, for request: Request,
                                currentTimelineFrame: Int) -> Bool {
        guard let expected = inFlight[request.id],
              expected == request, request.sessionID == sessionID,
              let (clip, localFrame) = location(at: request.timelineFrame),
              clip == request.clip, localFrame == request.localFrame else {
            rejectedCompletions += 1
            return false
        }
        inFlight.removeValue(forKey: request.id)
        guard request.timelineFrame >= currentTimelineFrame else {
            lateCompletions += 1
            return false
        }
        let size = pngData.count
        guard size > 0, size <= maximumReadyBytes else {
            rejectedCompletions += 1
            return false
        }
        while ready.count >= maximumReady ||
              readyBytes > maximumReadyBytes - size {
            guard let oldest = ready.keys.min(),
                  let evicted = ready.removeValue(forKey: oldest) else { break }
            readyBytes -= evicted.pngData.count
        }
        ready[request.timelineFrame] = Ready(request: request, pngData: pngData)
        readyBytes += size
        return true
    }

    /// A failed or cancelled decoder releases its reservation. Unknown or
    /// superseded tokens cannot clear a newer request's in-flight slot.
    public mutating func fail(_ request: Request) {
        if inFlight[request.id] == request {
            inFlight.removeValue(forKey: request.id)
        }
    }

    /// Never display another occurrence's pixels across a cut.
    /// If a frame has not arrived, a preceding verified frame may be held for
    /// at most maximumHoldFrames within that same occurrence. Otherwise blank.
    public mutating func presentation(at requestedFrame: Int) -> Presentation? {
        guard let (current, _) = location(at: requestedFrame),
              current.mediaKind == .video else { return nil }
        let lower = max(0, requestedFrame - maximumHoldFrames)
        for frame in stride(from: requestedFrame, through: lower, by: -1) {
            guard let entry = ready[frame], entry.request.clip.id == current.id,
                  entry.request.clip.takeID == current.takeID,
                  entry.request.clip.mediaSHA256 == current.mediaSHA256 else {
                continue
            }
            if frame < requestedFrame { skippedFrames += requestedFrame - frame }
            return Presentation(
                requestedFrame: requestedFrame, deliveredFrame: frame,
                occurrenceID: current.id, takeID: current.takeID,
                mediaSHA256: current.mediaSHA256, pngData: entry.pngData)
        }
        skippedFrames += 1
        return nil
    }

    /// Seek, project switch or stop: invalidate all pending request IDs and
    /// decoded frames; responses from earlier sessions fail the token check.
    public mutating func reset() {
        sessionID = UUID()
        inFlight.removeAll()
        ready.removeAll()
        readyBytes = 0
    }

    private mutating func retire(before frame: Int) {
        inFlight = inFlight.filter { $0.value.timelineFrame >= frame }
        let minimumReady = max(0, frame - maximumHoldFrames)
        for key in ready.keys.filter({ $0 < minimumReady }) {
            guard let removed = ready.removeValue(forKey: key) else { continue }
            readyBytes -= removed.pngData.count
        }
    }

    private func location(at timelineFrame: Int) -> (NativeAssemblyClip, Int)? {
        guard (0..<project.totalFrames).contains(timelineFrame) else { return nil }
        var cursor = 0
        for clip in project.clips {
            let end = cursor + clip.frameCount
            if timelineFrame < end { return (clip, timelineFrame - cursor) }
            cursor = end
        }
        return nil
    }
}
