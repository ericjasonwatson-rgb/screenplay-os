import AppKit
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

final class NativeVideoTimestampProbeTests: XCTestCase {
    private func syntheticVideo() async throws -> (folder: URL, source: URL, digest: String) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let mediaFolder = folder.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NativeAssemblyMovieExporter.Failure.invalidImage
        }
        try png.write(to: mediaFolder.appendingPathComponent("frame.png"))
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let frame = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: UUID(),
            boardFrameID: UUID(), takeID: UUID(), mediaSHA256: hash,
            mediaPath: "Board Images/frame.png", label: "Frame", frameCount: 48)
        let project = try NativeAssemblyProject(projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: String(repeating: "f", count: 64), clips: [frame]).validated()
        let video = folder.appendingPathComponent("source.mp4")
        try await NativeAssemblyMovieExporter.render(project,
            documentURL: folder.appendingPathComponent("synthetic.screenplayos.json"),
            outputURL: video)
        return (folder, video, try NativeVideoTakeImporter.digest(video))
    }

    func testProbeReadsRealDecodedVideoPresentationTimestamps() async throws {
        let fixture = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let index = try await NativeVideoTimestampProbe.inspect(
            fixture.source, expectedSHA256: fixture.digest)
        XCTAssertEqual(index.mediaSHA256, fixture.digest)
        XCTAssertGreaterThan(index.samples.count, 20)
        XCTAssertGreaterThan(index.trackID, 0)
        XCTAssertEqual(index.samples.first?.value, 0)
        let atHalfSecond = try index.sample(atTimelineFrame: 12)
        XCTAssertGreaterThanOrEqual(atHalfSecond.index, 10)
        XCTAssertLessThanOrEqual(atHalfSecond.index, 12)
        XCTAssertLessThanOrEqual(
            atHalfSecond.timestamp.cmTime.seconds, 0.5)
        let restored = try JSONDecoder().decode(
            NativeVideoPresentationIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(restored, index)
    }

    func testProbeRefusesSourceFingerprintMismatch() async throws {
        let fixture = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        do {
            _ = try await NativeVideoTimestampProbe.inspect(
                fixture.source, expectedSHA256: String(repeating: "0", count: 64))
            XCTFail("An unexpected media digest must be rejected")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
