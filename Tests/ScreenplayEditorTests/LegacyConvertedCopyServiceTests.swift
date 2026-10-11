import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Legacy converted-copy app bridge")
struct LegacyConvertedCopyServiceTests {
    private func fixture() throws -> (URL, URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.json")
        try Data("{}".utf8).write(to: source)
        let script = root.appendingPathComponent("fake.py")
        let body = #"""
import json, pathlib, sys
target = pathlib.Path(sys.argv[3]); target.mkdir()
print(json.dumps({"destination": str(target), "source_sha256": "abc", "project_revision": "revision", "payload_files": 4, "media_attachments": 2}))
"""#
        try Data(body.utf8).write(to: script)
        return (root, source, root.appendingPathComponent("Copy.screenplay"), script)
    }

    @Test func rejectsUnsupportedInputsBeforeLaunching() throws {
        let (root, source, destination, script) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LegacyConvertedCopyService(scriptURL: script, runtimeURL: URL(fileURLWithPath: "/usr/bin/python3"))
        #expect(throws: LegacyConvertedCopyService.Failure.self) {
            _ = try service.convert(source: source.deletingPathExtension().appendingPathExtension("txt"), destination: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        #expect(throws: LegacyConvertedCopyService.Failure.self) { _ = try service.convert(source: source, destination: destination) }
    }

    @Test func refusesToClaimSuccessUntilSwiftReadbackPasses() throws {
        let (root, source, destination, script) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = LegacyConvertedCopyService(scriptURL: script, runtimeURL: URL(fileURLWithPath: "/usr/bin/python3"))
        #expect(throws: LegacyConvertedCopyService.Failure.self) { _ = try service.convert(source: source, destination: destination) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: source) == Data("{}".utf8))
    }
}
