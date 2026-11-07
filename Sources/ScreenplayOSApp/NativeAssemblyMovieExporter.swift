import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import ScreenplayDomain

/// First milestone: offline H.264 boardomatic from still-image Takes only.
/// No audio/video-source decoding, provider requests, FilmCraft or egress.
enum NativeAssemblyMovieExporter {
    enum Failure: LocalizedError {
        case unsavedScreenplay, missingMedia, unsafeMedia, alteredMedia, invalidImage
        case outputExists, outputFailed, renderTooLong

        var errorDescription: String? {
            switch self {
            case .unsavedScreenplay: return "Save the screenplay beside its Board Images before exporting."
            case .missingMedia: return "A selected board image is missing."
            case .unsafeMedia: return "A board reference is outside the screenplay's Board Images folder."
            case .alteredMedia: return "A board image no longer matches its recorded SHA-256 fingerprint."
            case .invalidImage: return "A selected board image cannot be decoded."
            case .outputExists: return "The output file already exists. Choose a different filename."
            case .outputFailed: return "The MP4 writer could not complete the render."
            case .renderTooLong: return "The first assembly exporter supports up to five minutes."
            }
        }
    }

    private static let width = 1280
    private static let height = 720

    static func verifiedStill(_ clip: NativeAssemblyClip, documentURL: URL) throws -> URL {
        guard documentURL.isFileURL, NativeAssemblyProject.safeMediaPath(clip.mediaPath) else {
            throw Failure.unsafeMedia
        }
        let parent = documentURL.deletingLastPathComponent().standardizedFileURL
        let expected = parent.appendingPathComponent("Board Images", isDirectory: true).standardizedFileURL
        let candidate = parent.appendingPathComponent(clip.mediaPath).standardizedFileURL
        guard candidate.deletingLastPathComponent() == expected else { throw Failure.unsafeMedia }
        // Check the untrusted Board Images components rather than comparing a
        // globally canonicalized path. macOS may alias /var to /private/var.
        let folder = try? expected.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard folder?.isDirectory == true, folder?.isSymbolicLink == false else {
            throw Failure.unsafeMedia
        }
        let values = try? candidate.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isSymbolicLink == false else { throw Failure.unsafeMedia }
        guard values?.isRegularFile == true,
              let bytes = values?.fileSize, bytes > 0, bytes <= 20_000_000 else {
            throw Failure.missingMedia
        }
        let data = try Data(contentsOf: candidate, options: .mappedIfSafe)
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == clip.mediaSHA256 else { throw Failure.alteredMedia }
        guard CGImageSourceCreateWithURL(candidate as CFURL, nil) != nil else { throw Failure.invalidImage }
        return candidate
    }

    static func render(_ project: NativeAssemblyProject, documentURL: URL, outputURL: URL) async throws {
        _ = try project.validated()
        guard project.totalFrames > 0, project.totalFrames <= 5 * 60 * NativeAssemblyProject.framesPerSecond else {
            throw Failure.renderTooLong
        }
        guard outputURL.isFileURL, !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw Failure.outputExists
        }
        // Verify the complete timeline before creating an output or modifying disk.
        let sources = try project.clips.map { try verifiedStill($0, documentURL: documentURL) }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.outputFailed }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ])
        guard writer.startWriting() else { throw writer.error ?? Failure.outputFailed }
        writer.startSession(atSourceTime: .zero)
        var finished = false
        defer {
            if !finished {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        var frame = 0
        for (clip, source) in zip(project.clips, sources) {
            // Decode the exact bytes whose digest was checked, even if a
            // local source file changes after the initial preflight.
            let buffer = try renderPixelBuffer(source, expectedSHA256: clip.mediaSHA256)
            for _ in 0..<clip.frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let time = CMTime(value: CMTimeValue(frame),
                                  timescale: CMTimeScale(NativeAssemblyProject.framesPerSecond))
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw writer.error ?? Failure.outputFailed
                }
                frame += 1
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? Failure.outputFailed }
        finished = true
    }

    private static func renderPixelBuffer(_ url: URL, expectedSHA256: String) throws -> CVPixelBuffer {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw Failure.alteredMedia }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.invalidImage
        }
        var output: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32ARGB, attributes as CFDictionary,
                                  &output) == kCVReturnSuccess,
              let buffer = output else { throw Failure.outputFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { throw Failure.outputFailed }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let w = CGFloat(image.width) * scale
        let h = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2,
                                       y: (CGFloat(height) - h) / 2, width: w, height: h))
        return buffer
    }
}
