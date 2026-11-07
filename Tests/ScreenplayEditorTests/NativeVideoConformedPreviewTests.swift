import AppKit
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

/// Uses only two local synthetic images and a short H.264 file generated
/// by the actual ScreenplayOS assembly exporter.
final class NativeVideoConformedPreviewTests: XCTestCase {
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

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testPTSBoundPausedScrubPreservesSourceOffsetsAndRefusesTampering() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

        let red = try png(.red)
        let blue = try png(.blue)
        try red.write(to: media.appendingPathComponent("red.png"))
        try blue.write(to: media.appendingPathComponent("blue.png"))
        let shotID = UUID()
        let boardID = UUID()
        let clipA = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: shotID,
            boardFrameID: boardID, takeID: UUID(),
            mediaSHA256: sha(red), mediaPath: "Board Images/red.png",
            label: "Red", frameCount: 24)
        let clipB = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: shotID,
            boardFrameID: boardID, takeID: UUID(),
            mediaSHA256: sha(blue), mediaPath: "Board Images/blue.png",
            label: "Blue", frameCount: 24)
        let edit = try NativeAssemblyProject(projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: String(repeating: "e", count: 64),
            clips: [clipA, clipB]).validated()
        let screenplay = root.appendingPathComponent("synthetic.screenplayos.json")
        let rendered = root.appendingPathComponent("source.mp4")
        try await NativeAssemblyMovieExporter.render(
            edit, documentURL: screenplay, outputURL: rendered)

        let imported = try await NativeVideoTakeImporter.importLocalVideo(
            rendered, screenplayURL: screenplay, after: clipA)
        let preview = NativeVideoConformedPreview()
        let first = try await preview.frame(imported, localFrame: 5,
                                            screenplayURL: screenplay)
        let second = try await preview.frame(imported, localFrame: 30,
                                             screenplayURL: screenplay)
        XCTAssertEqual(first.requestedFrame, 5)
        XCTAssertEqual(second.requestedFrame, 30)
        XCTAssertNotNil(first.selectedSourceTimestamp)
        XCTAssertNotNil(second.selectedSourceTimestamp)
        XCTAssertEqual(first.selectedSampleIndex, 5)
        XCTAssertEqual(second.selectedSampleIndex, 30)
        XCTAssertNotEqual(sha(first.pngData), sha(second.pngData))

        var right = imported
        right.sourceInFrame = 24
        right.frameCount = 24
        let splitFrame = try await preview.frame(right, localFrame: 6,
                                                 screenplayURL: screenplay)
        XCTAssertEqual(splitFrame.requestedFrame, 30)
        XCTAssertEqual(splitFrame.selectedSampleIndex, 30)
        XCTAssertEqual(sha(splitFrame.pngData), sha(second.pngData))

        // A split occurrence and the original should reuse exactly the same
        // cached source PTS frame without sharing an editorial occurrence ID.
        let repeated = try await preview.frame(imported, localFrame: 30,
                                                screenplayURL: screenplay)
        XCTAssertEqual(repeated.pngData, second.pngData)
        XCTAssertEqual(repeated.requestedFrame, 30)
        #if DEBUG
        let diagnostics = await preview.cacheDiagnostics()
        XCTAssertGreaterThanOrEqual(diagnostics.hits, 2)
        XCTAssertLessThanOrEqual(diagnostics.frameCount, 16)
        XCTAssertLessThanOrEqual(diagnostics.bytes, 16 * 1024 * 1024)
        #endif

        let sourceCopy = root.appendingPathComponent(imported.mediaPath)
        try Data("altered video".utf8).write(to: sourceCopy)
        do {
            _ = try await preview.frame(imported, localFrame: 30,
                                        screenplayURL: screenplay)
            XCTFail("A cached index may never authorize changed source bytes")
        } catch NativeVideoFramePreview.Failure.alteredMedia {}
        await preview.clear()
    }
}
