import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

final class NativeAssemblyExportTests: XCTestCase {
    private func fixture() throws -> (root: URL, source: URL, assembly: NativeAssemblyProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let imageURL = folder.appendingPathComponent("synthetic.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        guard let data = bitmap?.representation(using: .png, properties: [:]) else {
            throw NativeAssemblyMovieExporter.Failure.invalidImage
        }
        try data.write(to: imageURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let clip = NativeAssemblyClip(sceneSpineID: "SC-001", shotID: UUID(),
            boardFrameID: UUID(), takeID: UUID(), mediaSHA256: hash,
            mediaPath: "Board Images/synthetic.png", label: "Synthetic still", frameCount: 24)
        let assembly = try NativeAssemblyProject(projectID: UUID(),
            sceneSpineID: "SC-001", boardRevision: String(repeating: "c", count: 64),
            clips: [clip]).validated()
        return (root, root.appendingPathComponent("synthetic.screenplayos.json"), assembly)
    }

    func testExportsPlayableOneSecondSilentMP4() async throws {
        let (root, document, assembly) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("boardomatic.mp4")
        try await NativeAssemblyMovieExporter.render(assembly, documentURL: document, outputURL: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.05)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertTrue(audio.isEmpty)
    }

    func testRefusesModifiedMediaBeforeWritingOutput() async throws {
        let (root, document, assembly) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Board Images/synthetic.png")
        try Data("modified input".utf8).write(to: image)
        let output = root.appendingPathComponent("should-not-exist.mp4")
        do {
            try await NativeAssemblyMovieExporter.render(assembly, documentURL: document, outputURL: output)
            XCTFail("Modified source cannot be rendered")
        } catch NativeAssemblyMovieExporter.Failure.alteredMedia {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
}
