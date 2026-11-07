import Foundation

/// A deterministic 24 fps editorial clock driven by a caller-supplied
/// monotonically increasing nanosecond counter (for example DispatchTime).
/// It never assumes Timer callbacks occur exactly once per frame.
///
/// This is a scheduler, not media decoding or an audio/video synchronization
/// guarantee. Missing display ticks skip stale frames rather than slowing time.
public struct NativeMonotonicPlaybackClock: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case invalidRange
    }

    public let totalFrames: Int
    public private(set) var isPlaying: Bool
    private var anchorFrame: Int
    private var anchorNanoseconds: UInt64

    private static let nanosPerSecond: UInt64 = 1_000_000_000
    private static let framesPerSecond: UInt64 = 24

    public init(totalFrames: Int, startFrame: Int = 0,
                startedAtNanoseconds: UInt64) throws {
        guard totalFrames > 0,
              totalFrames <= NativeAssemblyProject.maximumFrames,
              startFrame >= 0, startFrame <= totalFrames else {
            throw Failure.invalidRange
        }
        self.totalFrames = totalFrames
        anchorFrame = startFrame
        anchorNanoseconds = startedAtNanoseconds
        isPlaying = startFrame < totalFrames
    }

    public func frame(atNanoseconds now: UInt64) -> Int {
        guard isPlaying else { return anchorFrame }
        let elapsed = now >= anchorNanoseconds ? now - anchorNanoseconds : 0
        let remaining = UInt64(totalFrames - anchorFrame)
        // Limit elapsed time before multiplying to avoid overflow even if
        // an injected clock jumps forward by hundreds of years.
        let finishOffset = (remaining * Self.nanosPerSecond + Self.framesPerSecond - 1) /
            Self.framesPerSecond
        guard elapsed < finishOffset else { return totalFrames }
        let increment = (elapsed * Self.framesPerSecond) / Self.nanosPerSecond
        return anchorFrame + Int(increment)
    }

    /// Absolute monotonic deadline for the next change in the timeline frame.
    /// A delayed caller may skip directly to a later frame; no backfill occurs.
    public func nextFrameDeadline(afterNanoseconds now: UInt64) -> UInt64? {
        guard isPlaying else { return nil }
        let current = frame(atNanoseconds: now)
        guard current < totalFrames else { return nil }
        let next = UInt64(current - anchorFrame + 1)
        let offset = (next * Self.nanosPerSecond + Self.framesPerSecond - 1) /
            Self.framesPerSecond
        guard anchorNanoseconds <= UInt64.max - offset else { return nil }
        return anchorNanoseconds + offset
    }

    public mutating func pause(atNanoseconds now: UInt64) {
        anchorFrame = frame(atNanoseconds: now)
        anchorNanoseconds = now
        isPlaying = false
    }

    public mutating func resume(atNanoseconds now: UInt64) {
        anchorNanoseconds = now
        isPlaying = anchorFrame < totalFrames
    }

    public mutating func seek(toFrame frame: Int, atNanoseconds now: UInt64) throws {
        guard frame >= 0, frame <= totalFrames else { throw Failure.invalidRange }
        anchorFrame = frame
        anchorNanoseconds = now
        if frame == totalFrames { isPlaying = false }
    }
}
