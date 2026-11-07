import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ScreenplayDomain

/// A single, local video frame sampled at the assembly's 24 fps timebase.
/// This is a visual preview, NOT a claim of source-frame-accurate conform,
/// variable-frame-rate synchronization or video export capability.
enum NativeVideoFramePreview {
    enum Failure: LocalizedError {
        case notVideo, invalidRange, unsafeMedia, missingMedia, alteredMedia
        case decodeFailed, timestampMismatch

        var errorDescription: String? {
            switch self {
            case .notVideo: return "A video Take is required for video-frame preview."
            case .invalidRange: return "The requested video-frame position is outside this clip."
            case .unsafeMedia: return "The video source must stay in this project's Video Takes folder."
            case .missingMedia: return "The original video Take could not be found."
            case .alteredMedia: return "The video no longer matches its recorded SHA-256."
            case .decodeFailed: return "AVFoundation could not decode the requested video frame."
            case .timestampMismatch: return "The decoder returned a frame outside the requested time tolerance."
            }
        }
    }

    struct Decoded: Sendable {
        let pngData: Data
        let requestedFrame: Int
        let actualTimestampSeconds: Double
    }

    /// Uses the source-in plus a 0-based local frame offset; the timeline
    /// occurrence UUID is not used to infer which media file to open.
    static func preview(_ clip: NativeAssemblyClip, localFrame: Int,
                        screenplayURL: URL) async throws -> Decoded {
        let worker = Task.detached(priority: .userInitiated) {
            try decode(clip, localFrame: localFrame, screenplayURL: screenplayURL)
        }
        return try await withTaskCancellationHandler(operation: {
            try await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }

    private static func decode(_ clip: NativeAssemblyClip, localFrame: Int,
                               screenplayURL: URL) throws -> Decoded {
        try Task.checkCancellation()
        guard clip.mediaKind == .video else { throw Failure.notVideo }
        guard localFrame >= 0, localFrame < clip.frameCount,
              let frameLimit = clip.sourceFrameLimit, frameLimit > 0,
              clip.sourceInFrame >= 0,
              clip.sourceInFrame <= frameLimit - clip.frameCount else {
            throw Failure.invalidRange
        }
        guard screenplayURL.isFileURL,
              NativeAssemblyProject.safeMediaPath(clip.mediaPath, kind: .video) else {
            throw Failure.unsafeMedia
        }
        let sourceDir = screenplayURL.deletingLastPathComponent()
            .appendingPathComponent("Video Takes", isDirectory: true)
            .standardizedFileURL
        let file = screenplayURL.deletingLastPathComponent()
            .appendingPathComponent(clip.mediaPath).standardizedFileURL
        guard file.deletingLastPathComponent() == sourceDir else { throw Failure.unsafeMedia }
        let directory = try? sourceDir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory?.isDirectory == true, directory?.isSymbolicLink == false else {
            throw Failure.unsafeMedia
        }
        let fileInfo = try? file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard fileInfo?.isSymbolicLink == false else { throw Failure.unsafeMedia }
        guard fileInfo?.isRegularFile == true,
              let size = fileInfo?.fileSize, size > 0,
              size <= NativeVideoTakeImporter.maximumBytes else { throw Failure.missingMedia }

        // Source provenance check is expensive but intentionally performed
        // before a decoded image becomes visible in this unoptimized preview.
        do {
            try NativeVideoTakeImporter.verify(file, digest: clip.mediaSHA256)
        } catch {
            throw Failure.alteredMedia
        }
        try Task.checkCancellation()

        let sourceFrame = clip.sourceInFrame + localFrame
        let requested = CMTime(value: Int64(sourceFrame),
                               timescale: CMTimeScale(NativeAssemblyProject.framesPerSecond))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var actual = CMTime.invalid
        let image: CGImage
        do {
            image = try generator.copyCGImage(at: requested, actualTime: &actual)
        } catch {
            throw Failure.decodeFailed
        }
        try Task.checkCancellation()
        guard actual.isNumeric, actual.seconds.isFinite,
              abs(actual.seconds - requested.seconds) <=
                  (0.5 / Double(NativeAssemblyProject.framesPerSecond)) else {
            throw Failure.timestampMismatch
        }
        // Refuse a file that changes while the image generator was decoding.
        do {
            try NativeVideoTakeImporter.verify(file, digest: clip.mediaSHA256)
        } catch {
            throw Failure.alteredMedia
        }

        guard let png = NSBitmapImageRep(cgImage: image)
            .representation(using: .png, properties: [:]) else { throw Failure.decodeFailed }
        return Decoded(pngData: png, requestedFrame: sourceFrame,
                       actualTimestampSeconds: actual.seconds)
    }
}
