import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

/// The source is newly generated H.264 in the test runner. No camera media,
/// private projects, providers, internet access or external NLEs are involved.
final class NativeVideoRateConformTests: XCTestCase {
    private enum FixtureFailure: Error {
        case missingWriterInput, cannotStartWriter, cannotAppendFrame
        case cannotCreatePixelBuffer, cannotCreateContext, incompleteWriter
    }

    private let width = 320
    private let height = 180

    private func syntheticVideo(at url: URL, timestamps: [CMTime]) async throws {
        XCTAssertFalse(timestamps.isEmpty)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw FixtureFailure.missingWriterInput }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ])
        guard writer.startWriting() else { throw writer.error ?? FixtureFailure.cannotStartWriter }
        writer.startSession(atSourceTime: .zero)
        var finished = false
        defer {
            if !finished {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
        }
        for (index, timestamp) in timestamps.enumerated() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(try pixelBuffer(index: index, total: timestamps.count),
                                 withPresentationTime: timestamp) else {
                throw writer.error ?? FixtureFailure.cannotAppendFrame
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? FixtureFailure.incompleteWriter
        }
        finished = true
    }

    private func pixelBuffer(index: Int, total: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32ARGB, attributes as CFDictionary,
                                  &buffer) == kCVReturnSuccess,
              let buffer else { throw FixtureFailure.cannotCreatePixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ) else { throw FixtureFailure.cannotCreateContext }
        // Deliberately different first and second halves for image checking.
        let fill = index < total / 2
            ? CGColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1)
            : CGColor(red: 0.05, green: 0.05, blue: 0.85, alpha: 1)
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func fixture() throws -> (root: URL, screenplay: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("Synthetic.screenplayos.json"))
    }

    private func take(_ url: URL, screenplay: URL) async throws -> NativeAssemblyClip {
        let placeholder = NativeAssemblyClip(
            sceneSpineID: "SC-001", shotID: UUID(), boardFrameID: UUID(),
            takeID: UUID(), mediaSHA256: String(repeating: "a", count: 64),
            mediaPath: "Board Images/placeholder.png", label: "Placeholder", frameCount: 24)
        return try await NativeVideoTakeImporter.importLocalVideo(
            url, screenplayURL: screenplay, after: placeholder)
    }

    func testRationalRatesUseRealVideoSampleTimestamps() async throws {
        let cases: [(String, [CMTime], Int, Int)] = [
            ("23.976", (0..<24).map { CMTime(value: Int64($0) * 1001, timescale: 24_000) }, 1, 0),
            ("25", (0..<25).map { CMTime(value: Int64($0), timescale: 25) }, 1, 1),
            ("29.97", (0..<30).map { CMTime(value: Int64($0) * 1001, timescale: 30_000) }, 1, 1)
        ]
        for (label, timestamps, queryFrame, expectedIndex) in cases {
            let (root, _) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("rate-\(label).mp4")
            try await syntheticVideo(at: url, timestamps: timestamps)
            let index = try await NativeVideoTimestampProbe.inspect(
                url, expectedSHA256: NativeVideoTakeImporter.digest(url))
            XCTAssertEqual(index.samples.count, timestamps.count, label)
            for (position, expected) in timestamps.enumerated() {
                XCTAssertEqual(CMTimeCompare(index.samples[position].cmTime, expected),
                               0, "\(label) sample \(position)")
            }
            XCTAssertEqual(try index.sample(atTimelineFrame: queryFrame).index,
                           expectedIndex, label)
        }
    }

    func testVariableTimestampsAreHeldRatherThanInventingFrames() async throws {
        let (root, screenplay) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("irregular.mp4")
        let positions = [0, 1, 3, 10, 20, 21]
        let stamps = positions.map { CMTime(value: Int64($0), timescale: 24) }
        try await syntheticVideo(at: source, timestamps: stamps)
        let imported = try await take(source, screenplay: screenplay)
        let index = try await NativeVideoTimestampProbe.inspect(
            root.appendingPathComponent(imported.mediaPath),
            expectedSHA256: imported.mediaSHA256)
        XCTAssertEqual(index.samples.count, positions.count)
        XCTAssertEqual(try index.sample(atTimelineFrame: 4).index, 2)
        XCTAssertEqual(try index.sample(atTimelineFrame: 9).index, 2)
        XCTAssertEqual(try index.sample(atTimelineFrame: 10).index, 3)

        let viewer = NativeVideoConformedPreview()
        let before = try await viewer.frame(imported, localFrame: 4, screenplayURL: screenplay)
        let after = try await viewer.frame(imported, localFrame: 20, screenplayURL: screenplay)
        XCTAssertEqual(before.selectedSampleIndex, 2)
        XCTAssertEqual(after.selectedSampleIndex, 4)
        guard let beforePTS = before.selectedSourceTimestamp,
              let afterPTS = after.selectedSourceTimestamp else {
            return XCTFail("The conformed preview must return a verified source PTS")
        }
        XCTAssertEqual(beforePTS.cmTime.seconds, 3.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(afterPTS.cmTime.seconds, 20.0 / 24.0, accuracy: 0.0001)
        XCTAssertNotEqual(before.pngData, after.pngData)
    }
}
