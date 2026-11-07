import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

/// Synthetic media only: two deliberately different board images are encoded
/// as a local H.264 video, then decoded through the actual preview code.
final class NativeVideoFramePreviewTests: XCTestCase {
    private func png(_ color: NSColor) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw NativeVideoFramePreview.Failure.decodeFailed }
        for y in 0..<18 {
            for x in 0..<32 { bitmap.setColor(color, atX: x, y: y) }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NativeVideoFramePreview.Failure.decodeFailed
        }
        return data
    }

    private func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func testScrubReturnsTwoDistinctSourceFramesAndRejectsTampering() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let red = try png(.red)
        let blue = try png(.blue)
        try red.write(to: folder.appendingPathComponent("red.png"))
        try blue.write(to: folder.appendingPathComponent("blue.png"))
        let boardID = UUID()
        let shotID = UUID()
        let first = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: shotID,
            boardFrameID: boardID, takeID: UUID(), mediaSHA256: hash(red),
            mediaPath: "Board Images/red.png", label: "Red", frameCount: 24)
        let second = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: shotID,
            boardFrameID: boardID, takeID: UUID(), mediaSHA256: hash(blue),
            mediaPath: "Board Images/blue.png", label: "Blue", frameCount: 24)
        let assembly = try NativeAssemblyProject(projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: String(repeating: "c", count: 64),
            clips: [first, second]).validated()
        let screenplay = root.appendingPathComponent("Synthetic.screenplayos.json")
        let source = root.appendingPathComponent("two-colors.mp4")
        try await NativeAssemblyMovieExporter.render(assembly,
            documentURL: screenplay, outputURL: source)
        let imported = try await NativeVideoTakeImporter.importLocalVideo(
            source, screenplayURL: screenplay, after: first)

        let frameA = try await NativeVideoFramePreview.preview(
            imported, localFrame: 5, screenplayURL: screenplay)
        let frameB = try await NativeVideoFramePreview.preview(
            imported, localFrame: 30, screenplayURL: screenplay)
        XCTAssertEqual(frameA.requestedFrame, 5)
        XCTAssertEqual(frameB.requestedFrame, 30)
        XCTAssertNotEqual(hash(frameA.pngData), hash(frameB.pngData))
        XCTAssertEqual(frameA.actualTimestampSeconds, 5.0 / 24.0, accuracy: 1.0 / 48.0)
        XCTAssertEqual(frameB.actualTimestampSeconds, 30.0 / 24.0, accuracy: 1.0 / 48.0)
        XCTAssertNotNil(NSImage(data: frameA.pngData))
        XCTAssertNotNil(NSImage(data: frameB.pngData))

        var right = imported
        right.sourceInFrame = 24
        right.frameCount = 24
        let afterSplit = try await NativeVideoFramePreview.preview(
            right, localFrame: 0, screenplayURL: screenplay)
        XCTAssertEqual(afterSplit.requestedFrame, 24)
        XCTAssertEqual(hash(afterSplit.pngData), hash(
            try await NativeVideoFramePreview.preview(
                imported, localFrame: 24, screenplayURL: screenplay).pngData))

        do {
            _ = try await NativeVideoFramePreview.preview(
                imported, localFrame: 48, screenplayURL: screenplay)
            XCTFail("Out-of-range preview must fail")
        } catch NativeVideoFramePreview.Failure.invalidRange {}

        let copied = root.appendingPathComponent(imported.mediaPath)
        try Data("tampered".utf8).write(to: copied)
        do {
            _ = try await NativeVideoFramePreview.preview(
                imported, localFrame: 0, screenplayURL: screenplay)
            XCTFail("Changed media may not be previewed as a trusted Take")
        } catch NativeVideoFramePreview.Failure.alteredMedia {}
    }
}
