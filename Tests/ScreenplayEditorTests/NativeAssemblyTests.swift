import Foundation
import XCTest
@testable import ScreenplayDomain

final class NativeAssemblyTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    private func boards() -> [BoardFrame] {
        (0..<2).map { index in
            var frame = BoardFrame(shotID: UUID(), sceneSpineID: "SC-001",
                                   frameNumber: index + 1, label: "Board \(index + 1)",
                                   durationSeconds: 2)
            let image = BoardImageVersion(
                fileURL: URL(string: "Board%20Images/board\(index + 1).png")!,
                sha256: digest, prompt: "A test image", model: "local")
            frame.imageVersions = [image]
            frame.selectedImageID = image.id
            return frame
        }
    }

    func testAssembleAndSaveReopenWithoutLosingTakeIdentity() throws {
        let projectID = UUID()
        let boards = boards()
        let assembled = try NativeAssemblyProject.assemble(
            projectID: projectID, sceneSpineID: "SC-001", boards: boards)
        XCTAssertEqual(assembled.clips.count, 2)
        XCTAssertEqual(assembled.totalFrames, 96)
        XCTAssertEqual(assembled.clips[0].takeID, boards[0].selectedImageID)
        XCTAssertNotEqual(assembled.clips[0].id, assembled.clips[0].takeID)
        XCTAssertTrue(assembled.isCurrent(with: boards))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try NativeAssemblyFileStore.url(
            projectID: projectID, sceneSpineID: "SC-001", root: root)
        try NativeAssemblyFileStore.save(assembled, to: url)
        let loaded = try NativeAssemblyFileStore.load(
            from: url, projectID: projectID, sceneSpineID: "SC-001")
        XCTAssertEqual(loaded, assembled)
        XCTAssertEqual(loaded.clip(at: 0)?.takeID, boards[0].selectedImageID)
        XCTAssertEqual(loaded.clip(at: 48)?.takeID, boards[1].selectedImageID)
        XCTAssertNil(loaded.clip(at: 96))
    }

    func testTrimSplitDuplicateAndMovePreserveProvenance() throws {
        let source = try NativeAssemblyProject.assemble(
            projectID: UUID(), sceneSpineID: "SC-001", boards: boards())
        let original = source.clips[0]
        let splitID = UUID()
        let split = try source.splitting(original.id, afterFrames: 24, newOccurrenceID: splitID)
        XCTAssertEqual(split.totalFrames, source.totalFrames)
        XCTAssertEqual(split.clips[0].frameCount, 24)
        XCTAssertEqual(split.clips[1].frameCount, 24)
        XCTAssertEqual(split.clips[1].takeID, original.takeID)
        XCTAssertEqual(split.clips[1].mediaSHA256, original.mediaSHA256)
        XCTAssertNotEqual(split.clips[0].id, split.clips[1].id)
        let shortened = try split.trimming(splitID, toFrames: 12)
        XCTAssertEqual(shortened.totalFrames, source.totalFrames - 12)
        let duplicate = try shortened.duplicating(original.id)
        XCTAssertEqual(duplicate.clips[0].takeID, duplicate.clips[1].takeID)
        XCTAssertNotEqual(duplicate.clips[0].id, duplicate.clips[1].id)
        let moved = try duplicate.moving(original.id, by: 1)
        XCTAssertEqual(moved.clips[1].id, original.id)
        XCTAssertEqual(source.totalFrames, 96, "All edits must return a new value")
    }

    func testRejectsForgedOrAmbiguousOccurrences() throws {
        let source = try NativeAssemblyProject.assemble(
            projectID: UUID(), sceneSpineID: "SC-001", boards: boards())
        var duplicate = source
        duplicate.clips[1].id = duplicate.clips[0].id
        XCTAssertThrowsError(try duplicate.validated())
        var tampered = source
        tampered.clips[0].mediaPath = "../secrets.png"
        XCTAssertThrowsError(try tampered.validated())
        tampered = source
        tampered.clips[0].mediaSHA256 = "not-a-digest"
        XCTAssertThrowsError(try tampered.validated())
        XCTAssertThrowsError(try source.splitting(source.clips[0].id, afterFrames: 0))
        XCTAssertThrowsError(try source.duplicating(source.clips[0].id,
                                                    newOccurrenceID: source.clips[1].id))
        XCTAssertThrowsError(try source.moving(source.clips[0].id, by: -1))
    }

    func testBoardChangesCannotBeMistakenForCurrentAssembly() throws {
        let initial = boards()
        let assembled = try NativeAssemblyProject.assemble(
            projectID: UUID(), sceneSpineID: "SC-001", boards: initial)
        var changed = initial
        changed[0].imageVersions[0].sha256 = String(repeating: "b", count: 64)
        XCTAssertFalse(assembled.isCurrent(with: changed))
        XCTAssertTrue(assembled.isCurrent(with: initial))
    }

    func testRefusesSymlinkedSidecarDirectory() throws {
        let project = try NativeAssemblyProject.assemble(
            projectID: UUID(), sceneSpineID: "SC-001", boards: boards())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let redirected = root.appendingPathComponent("unexpected")
        let parent = root.appendingPathComponent("ScreenplayOS")
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: parent.appendingPathComponent("NativeAssemblies"),
            withDestinationURL: redirected)
        let path = try NativeAssemblyFileStore.url(
            projectID: project.projectID, sceneSpineID: project.sceneSpineID, root: root)
        XCTAssertThrowsError(try NativeAssemblyFileStore.save(project, to: path))
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: redirected.path)).isEmpty)
    }

    func testRejectsWrongProjectAtLoad() throws {
        let project = try NativeAssemblyProject.assemble(
            projectID: UUID(), sceneSpineID: "SC-001", boards: boards())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try NativeAssemblyFileStore.url(
            projectID: project.projectID, sceneSpineID: project.sceneSpineID, root: root)
        try NativeAssemblyFileStore.save(project, to: path)
        XCTAssertThrowsError(try NativeAssemblyFileStore.load(
            from: path, projectID: UUID(), sceneSpineID: "SC-001"))
    }
}
