import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ScreenplayDomain

/// A read-only enumeration of actual source presentation timestamps.
/// No project mutation, media conversion, provider access or NLE import.
enum NativeVideoTimestampProbe {
    enum Failure: LocalizedError {
        case invalidSource, invalidTrack, invalidDuration, unreadableSamples, unsupportedTimestamp
        case readerConfiguration, readerStart, readerCompletion
        case mediaChanged, tooManySamples

        var errorDescription: String? {
            switch self {
            case .invalidSource: return "Only verified ordinary local MOV or MP4 media can be inspected."
            case .invalidTrack: return "A single valid video track is required for this timestamp probe."
            case .invalidDuration: return "The source has no valid presentation duration."
            case .unreadableSamples: return "The source's video samples cannot be inspected."
            case .readerConfiguration: return "The local video reader cannot be configured for frame timestamps."
            case .readerStart: return "The local video reader failed to start."
            case .readerCompletion: return "The local video reader did not finish reading all frames."
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
        // Decoded sample output is supported where passthrough compressed
        // samples are not. This probe uses the sample PTS only; pixel data is
        // discarded immediately rather than cached or exported.
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.readerConfiguration }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.readerStart }
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
        guard reader.status == .completed else { throw reader.error ?? Failure.readerCompletion }
        // Presentation timestamps are sorted even if a decoder or media
        // reader delivers samples in a different internal order.
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
