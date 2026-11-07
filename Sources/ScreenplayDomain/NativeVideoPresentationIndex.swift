import CoreMedia
import Foundation

/// Source presentation timestamps are recorded as exact CMTime rational pairs.
/// Timeline positions remain integer 24 fps frames; this index explicitly
/// resolves them against actual video timestamps (including VFR material).
public struct NativeVideoTimestamp: Codable, Equatable, Sendable {
    public var value: Int64
    public var timescale: Int32

    public init(value: Int64, timescale: Int32) {
        self.value = value
        self.timescale = timescale
    }

    public var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
}

public enum NativeVideoTimestampError: Error, Equatable {
    case unsupportedVersion, invalidSource, invalidTimestamp, duplicateOrUnorderedTimestamp
    case emptyIndex, tooManySamples, outsideSourceRange, beforeFirstSample
}

/// Read-only source PTS index. It is NOT a substitute for the video Take ID or
/// the SHA-256 of the original media. No timeline edits are made by this type.
public struct NativeVideoPresentationIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumSamples = 250_000

    public let version: Int
    public let mediaSHA256: String
    public let trackID: Int32
    public let duration: NativeVideoTimestamp
    /// Strictly increasing presentation times, not decoder delivery order.
    public let samples: [NativeVideoTimestamp]

    public init(mediaSHA256: String, trackID: Int32, duration: NativeVideoTimestamp,
                samples: [NativeVideoTimestamp], version: Int = currentVersion) throws {
        self.version = version
        self.mediaSHA256 = mediaSHA256
        self.trackID = trackID
        self.duration = duration
        self.samples = samples
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case version, mediaSHA256, trackID, duration, samples
    }

    /// Persisted indexes are untrusted until validated. Synthesized Decodable
    /// would otherwise bypass the checks performed by the public initializer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        mediaSHA256 = try container.decode(String.self, forKey: .mediaSHA256)
        trackID = try container.decode(Int32.self, forKey: .trackID)
        duration = try container.decode(NativeVideoTimestamp.self, forKey: .duration)
        samples = try container.decode([NativeVideoTimestamp].self, forKey: .samples)
        try validate()
    }

    public func validate() throws {
        guard version == Self.currentVersion else { throw NativeVideoTimestampError.unsupportedVersion }
        guard NativeAssemblyProject.digest(mediaSHA256), trackID > 0 else {
            throw NativeVideoTimestampError.invalidSource
        }
        guard !samples.isEmpty else { throw NativeVideoTimestampError.emptyIndex }
        guard samples.count <= Self.maximumSamples else { throw NativeVideoTimestampError.tooManySamples }
        guard Self.valid(duration), duration.value > 0 else {
            throw NativeVideoTimestampError.invalidTimestamp
        }
        var previous: CMTime?
        for sample in samples {
            guard Self.valid(sample), CMTimeCompare(sample.cmTime, duration.cmTime) < 0 else {
                throw NativeVideoTimestampError.invalidTimestamp
            }
            if let previous, CMTimeCompare(sample.cmTime, previous) <= 0 {
                throw NativeVideoTimestampError.duplicateOrUnorderedTimestamp
            }
            previous = sample.cmTime
        }
    }

    /// Read-only binding between one editorial occurrence and a PTS index.
    /// A source fingerprint mismatch must never silently select another Take's
    /// timestamps. The model still requires explicit source conformance later.
    public func sample(for clip: NativeAssemblyClip, localFrame: Int) throws
        -> (index: Int, timestamp: NativeVideoTimestamp) {
        guard clip.mediaKind == .video, clip.mediaSHA256 == mediaSHA256 else {
            throw NativeVideoTimestampError.invalidSource
        }
        guard localFrame >= 0, localFrame < clip.frameCount,
              let sourceLimit = clip.sourceFrameLimit, sourceLimit > 0,
              clip.sourceInFrame >= 0,
              clip.sourceInFrame <= sourceLimit - clip.frameCount else {
            throw NativeVideoTimestampError.outsideSourceRange
        }
        return try sample(atTimelineFrame: clip.sourceInFrame + localFrame)
    }

    /// The visible source sample at a 24 fps edit-time position is the latest
    /// presentation timestamp that is <= that instant. Holding an earlier
    /// frame across a VFR interval is intentional and deterministic.
    public func sample(atTimelineFrame frame: Int) throws -> (index: Int, timestamp: NativeVideoTimestamp) {
        guard frame >= 0, frame <= NativeAssemblyProject.maximumFrames else {
            throw NativeVideoTimestampError.outsideSourceRange
        }
        let request = CMTime(value: Int64(frame),
                             timescale: CMTimeScale(NativeAssemblyProject.framesPerSecond))
        guard CMTimeCompare(request, duration.cmTime) < 0 else {
            throw NativeVideoTimestampError.outsideSourceRange
        }
        guard let first = samples.first, CMTimeCompare(request, first.cmTime) >= 0 else {
            throw NativeVideoTimestampError.beforeFirstSample
        }
        var low = 0
        var high = samples.count
        while low < high {
            let middle = low + (high - low) / 2
            if CMTimeCompare(samples[middle].cmTime, request) <= 0 {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        return (index, samples[index])
    }

    private static func valid(_ timestamp: NativeVideoTimestamp) -> Bool {
        timestamp.timescale > 0 && timestamp.value >= 0 &&
            timestamp.cmTime.isNumeric
    }
}
