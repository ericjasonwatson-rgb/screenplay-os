import AVFoundation
import CoreMedia
import Foundation
import ScreenplayDomain

/// A read-only enumeration of actual source presentation timestamps.
/// No project mutation, media conversion, provider access or NLE import.
enum NativeVideoTimestampProbe {
    enum Failure: LocalizedError {
        case invalidSource, invalidTrack, invalidDuration, unreadableSamples, unsupportedTimestamp
        case mediaChanged, tooManySamples

        var errorDescription: String? {
            switch self {
            case .invalidSource: return "Only verified ordinary local MOV or MP4 media can be inspected."
            case .invalidTrack: return "A single valid video track is required for this timestamp probe."
            case .invalidDuration: return "The source has no valid presentation duration."
            case .unreadableSamples: return "The source's compressed video samples cannot be inspected."
            case .unsupportedTimestamp: return "Source timestamps are invalid or not representable."
            case .mediaChanged: return "The original video changed while its timestamps were inspected."
            case .tooManySamples: return "The source exceeds the timestamp-index sample limit."
            }
        }
    }

    static func inspect(_ url: URL, expectedSHA256: String) async throws -> NativeVideoPresentationIndex {
        guard url.isFileURL,
              ["mov", "mp4"].contains(url.pathExtension.lowercased()),
              NativeAssemblyProject.digest(expectedSHA256) else {
            throw Failure.invalidSource
        }
        try NativeVideoTakeImporter.verify(url, digest: expectedSHA256)
        let worker = Task.detached(priority: .utility) {
            try await read(url, expectedSHA256: expectedSHA256)
        }
        return try await withTaskCancellationHandler(operation: {
            try await worker.value
        }, onCancel: { worker.cancel() })
    }

    private static func read(_ url: URL, expectedSHA256: String) async throws -> NativeVideoPresentationIndex {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1 else { throw Failure.invalidTrack }
        let track = tracks[0]
        let duration = try await asset.load(.duration)
        guard let durationTime = timestamp(duration), durationTime.value > 0 else {
            throw Failure.invalidDuration
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw Failure.unreadableSamples }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.unreadableSamples }
        defer { if reader.status == .reading { reader.cancelReading() } }

        var times: [NativeVideoTimestamp] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0 else { throw Failure.unreadableSamples }
            for position in 0..<count {
                var info = CMSampleTimingInfo()
                guard CMSampleBufferGetSampleTimingInfo(sample, at: position,
                                                        timingInfoOut: &info) == noErr,
                      let time = timestamp(info.presentationTimeStamp) else {
                    throw Failure.unsupportedTimestamp
                }
                times.append(time)
                guard times.count <= NativeVideoPresentationIndex.maximumSamples else {
                    throw Failure.tooManySamples
                }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? Failure.unreadableSamples }
        // Compressed samples can arrive in decoding rather than presentation
        // order (for example with B-frames). Never mistake decode order for PTS.
        times.sort { CMTimeCompare($0.cmTime, $1.cmTime) < 0 }

        try NativeVideoTakeImporter.verify(url, digest: expectedSHA256)
        try Task.checkCancellation()
        return try NativeVideoPresentationIndex(
            mediaSHA256: expectedSHA256,
            trackID: Int32(track.trackID),
            duration: durationTime,
            samples: times
        )
    }

    private static func timestamp(_ time: CMTime) -> NativeVideoTimestamp? {
        guard time.isNumeric, time.timescale > 0, time.value >= 0 else { return nil }
        return NativeVideoTimestamp(value: time.value, timescale: time.timescale)
    }
}
