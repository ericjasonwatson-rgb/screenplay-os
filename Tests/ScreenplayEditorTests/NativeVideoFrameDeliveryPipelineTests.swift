import AppKit
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

final class NativeVideoFrameDeliveryPipelineTests: XCTestCase {
    private func png(_ color: NSColor) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw NativeAssemblyMovieExporter.Failure.invalidImage }
        for y in 0..<18 {
            for x in 0..<32 { bitmap.setColor(color, atX: x, y: y) }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NativeAssemblyMovieExporter.Failure.invalidImage
        }
        return png
    }

    private func sha(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func testClockSelectedSourceDeliveryAndTamperInvalidation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let red = try png(.red)
        let blue = try png(.blue)
        try red.write(to: images.appendingPathComponent("red.png"))
        try blue.write(to: images.appendingPathComponent("blue.png"))
        let shotID = UUID(), boardID = UUID()
        let first = NativeAssemblyClip(
            sceneSpineID: "SC-001", shotID: shotID, boardFrameID: boardID,
            takeID: UUID(), mediaSHA256: sha(red), mediaPath: "Board Images/red.png",
            label: "First", frameCount: 24)
        let second = NativeAssemblyClip(
            sceneSpineID: "SC-001", shotID: shotID, boardFrameID: boardID,
            takeID: UUID(), mediaSHA256: sha(blue), mediaPath: "Board Images/blue.png",
            label: "Second", frameCount: 24)
        let sourceEdit = try NativeAssemblyProject(
            projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: String(repeating: "b", count: 64),
            clips: [first, second]).validated()
        let screenplay = root.appendingPathComponent("Synthetic.screenplayos.json")
        let movie = root.appendingPathComponent("source.mp4")
        try await NativeAssemblyMovieExporter.render(
            sourceEdit, documentURL: screenplay, outputURL: movie)
        let take = try await NativeVideoTakeImporter.importLocalVideo(
            movie, screenplayURL: screenplay, after: first)
        let timeline = try NativeAssemblyProject(
            projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: String(repeating: "c", count: 64),
            clips: [take]).validated()
        let pipeline = try NativeVideoFrameDeliveryPipeline(
            project: timeline, screenplayURL: screenplay)

        // Tick initiates decoding without blocking on it. A later tick can
        // present a completed frame; it must never fabricate an early image.
        let initial = await pipeline.tick(atTimelineFrame: 0)
        XCTAssertNil(initial)
        await pipeline.drainCurrentRequests()
        guard let firstFrame = await pipeline.tick(atTimelineFrame: 0) else {
            return XCTFail("Source PTS frame 0 was not delivered")
        }
        XCTAssertEqual(firstFrame.deliveredFrame, 0)
        XCTAssertEqual(firstFrame.occurrenceID, take.id)
        XCTAssertEqual(firstFrame.takeID, take.takeID)
        XCTAssertEqual(firstFrame.mediaSHA256, take.mediaSHA256)

        // Simulate a stalled display clock jumping over 23 frames. The next
        // delivered frame is selected by the clock, not backfilled in order.
        _ = await pipeline.tick(atTimelineFrame: 24)
        await pipeline.drainCurrentRequests()
        guard let secondFrame = await pipeline.tick(atTimelineFrame: 24) else {
            return XCTFail("Frame at the new clock position was not delivered")
        }
        XCTAssertEqual(secondFrame.deliveredFrame, 24)
        XCTAssertNotEqual(firstFrame.pngData, secondFrame.pngData)

        let stats = await pipeline.diagnostics()
        XCTAssertLessThanOrEqual(stats.ready, 4)
        XCTAssertLessThanOrEqual(stats.readyBytes, 16 * 1024 * 1024)
        XCTAssertLessThanOrEqual(stats.inFlight, 2)
        XCTAssertEqual(stats.decodeFailures, 0)

        // A previously ready frame must not bypass source-media validation.
        let importedFile = root.appendingPathComponent(take.mediaPath)
        try Data("tampered source".utf8).write(to: importedFile)
        let tampered = await pipeline.tick(atTimelineFrame: 24)
        XCTAssertNil(tampered)
        let invalidated = await pipeline.diagnostics()
        XCTAssertEqual(invalidated.ready, 0)
        XCTAssertGreaterThan(invalidated.decodeFailures, 0)
        await pipeline.reset()
    }
}
