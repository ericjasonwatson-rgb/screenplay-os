import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ScreenplayDomain
import XCTest
@testable import ScreenplayOSApp

final class NativeAssemblyVideoTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    private func still() -> NativeAssemblyClip {
        NativeAssemblyClip(sceneSpineID: "SC-001", shotID: UUID(), boardFrameID: UUID(),
                           takeID: UUID(), mediaSHA256: digest,
                           mediaPath: "Board Images/board.png", label: "Board",
                           frameCount: 48)
    }

    private func video(after parent: NativeAssemblyClip) -> NativeAssemblyClip {
        NativeAssemblyClip(sceneSpineID: parent.sceneSpineID, shotID: parent.shotID,
                           boardFrameID: parent.boardFrameID, takeID: UUID(),
                           mediaSHA256: digest, mediaPath: "Video Takes/clip.mov",
                           label: "Clip", frameCount: 72, mediaKind: .video,
                           sourceInFrame: 12, sourceFrameLimit: 100)
    }

    private func project(_ clips: [NativeAssemblyClip], version: Int = NativeAssemblyProject.currentVersion) -> NativeAssemblyProject {
        NativeAssemblyProject(projectID: UUID(), sceneSpineID: "SC-001",
                              boardRevision: digest, clips: clips, version: version)
    }

    func testVideoSplitAndHeadTrimPreserveExactSourceFrames() throws {
        let board = still()
        let movie = video(after: board)
        let initial = try project([board]).insertingVideoTake(movie, after: board.id)
        XCTAssertEqual(initial.totalFrames, 120)
        let split = try initial.splitting(movie.id, afterFrames: 24,
                                          newOccurrenceID: UUID())
        let left = split.clips[1]
        let right = split.clips[2]
        XCTAssertEqual(left.sourceInFrame, 12)
        XCTAssertEqual(left.frameCount, 24)
        XCTAssertEqual(right.sourceInFrame, 36)
        XCTAssertEqual(right.frameCount, 48)
        XCTAssertEqual(right.takeID, left.takeID)
        XCTAssertNotEqual(right.id, left.id)
        XCTAssertEqual(right.mediaSHA256, left.mediaSHA256)
        let cut = try split.trimmingHead(right.id, byFrames: 10)
        XCTAssertEqual(cut.clips[2].sourceInFrame, 46)
        XCTAssertEqual(cut.clips[2].frameCount, 38)
        let duplicate = try cut.duplicating(right.id)
        XCTAssertEqual(duplicate.clips[3].sourceInFrame, 46)
        XCTAssertEqual(duplicate.clips[3].takeID, right.takeID)
        XCTAssertNotEqual(duplicate.clips[3].id, right.id)
    }

    func testRefusesOutOfSourceRangeAndUnsafeVideoPath() throws {
        let board = still()
        var movie = video(after: board)
        movie.sourceInFrame = 40
        XCTAssertThrowsError(try project([board, movie]).validated())
        movie.sourceInFrame = -1
        XCTAssertThrowsError(try project([board, movie]).validated())
        movie.sourceInFrame = 0
        movie.sourceFrameLimit = nil
        XCTAssertThrowsError(try project([board, movie]).validated())
        movie.sourceFrameLimit = 100
        movie.mediaPath = "../outside.mov"
        XCTAssertThrowsError(try project([board, movie]).validated())
        movie.mediaPath = "Video Takes/clip.mov"
        XCTAssertNoThrow(try project([board, movie]).validated())
    }

    func testExistingV1StillProjectUpgradesWithoutInventingVideo() throws {
        let old = project([still()], version: 1)
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        var clips = data["clips"] as! [[String: Any]]
        clips[0].removeValue(forKey: "mediaKind")
        clips[0].removeValue(forKey: "sourceInFrame")
        clips[0].removeValue(forKey: "sourceFrameLimit")
        data["clips"] = clips
        let bytes = try JSONSerialization.data(withJSONObject: data)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("old.json")
        try bytes.write(to: file)
        let restored = try NativeAssemblyFileStore.load(
            from: file, projectID: old.projectID, sceneSpineID: old.sceneSpineID)
        XCTAssertEqual(restored.version, 2)
        XCTAssertEqual(restored.clips[0].mediaKind, .stillImage)
        XCTAssertEqual(restored.clips[0].sourceInFrame, 0)
        XCTAssertNil(restored.clips[0].sourceFrameLimit)
        try NativeAssemblyFileStore.save(restored, to: file)
        XCTAssertEqual(try NativeAssemblyFileStore.load(
            from: file, projectID: old.projectID, sceneSpineID: old.sceneSpineID), restored)
    }

    func testImportedLocalVideoIsHashVerifiedAndNotSilentlyExported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        guard let png = bitmap?.representation(using: .png, properties: [:]) else {
            throw NativeAssemblyMovieExporter.Failure.invalidImage
        }
        let imageURL = images.appendingPathComponent("board.png")
        try png.write(to: imageURL)
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        var board = still()
        board.mediaSHA256 = hash
        board.frameCount = 24
        let base = try project([board]).validated()
        let screenplay = root.appendingPathComponent("synthetic.screenplayos.json")
        let source = root.appendingPathComponent("source.mp4")
        try await NativeAssemblyMovieExporter.render(base,
            documentURL: screenplay, outputURL: source)
        let imported = try await NativeVideoTakeImporter.importLocalVideo(
            source, screenplayURL: screenplay, after: board)
        XCTAssertEqual(imported.mediaKind, .video)
        XCTAssertEqual(imported.frameCount, 24)
        XCTAssertEqual(imported.sourceInFrame, 0)
        XCTAssertEqual(imported.sourceFrameLimit, 24)
        XCTAssertNotEqual(imported.takeID, board.takeID)
        XCTAssertTrue(imported.mediaPath.hasPrefix("Video Takes/"))
        let copy = root.appendingPathComponent(imported.mediaPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try NativeVideoTakeImporter.digest(copy), imported.mediaSHA256)
        let edited = try base.insertingVideoTake(imported, after: board.id)
        let sidecar = root.appendingPathComponent("assembly.json")
        try NativeAssemblyFileStore.save(edited, to: sidecar)
        let reopened = try NativeAssemblyFileStore.load(
            from: sidecar, projectID: edited.projectID, sceneSpineID: edited.sceneSpineID)
        XCTAssertEqual(reopened, edited)
        do {
            try await NativeAssemblyMovieExporter.render(edited,
                documentURL: screenplay, outputURL: root.appendingPathComponent("blocked.mp4"))
            XCTFail("Silent boardomatic export must not misrender a video Take")
        } catch NativeAssemblyMovieExporter.Failure.unsupportedVideoTake {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("blocked.mp4").path))
        }
    }
}
