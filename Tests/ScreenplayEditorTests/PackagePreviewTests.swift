import CryptoKit
import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Read-only package preview")
@MainActor
struct PackagePreviewTests {
    private func makePackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("screenplay")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("provenance"), withIntermediateDirectories: true)
        let id = UUID().uuidString
        let manifest: [String: Any] = ["format": "open-screenplay", "format_version": "1.0", "document_id": id, "title": "Preview fixture"]
        let script: [String: Any] = ["id": id, "elements": [
            ["id": UUID().uuidString, "type": "scene_heading", "text": "INT. ROOM - DAY"],
            ["id": UUID().uuidString, "type": "future_type", "text": "e\u{301} 👩🏽‍🚀\nExact text"],
            ["id": UUID().uuidString, "type": "action", "text": ""]]]
        var inventory: [String: Any] = [:]
        for (name, object) in ["manifest.json": manifest, "screenplay.json": script, "extensions.json": ["extensions": [:]]] {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent(name))
            inventory[name] = ["sha256": digest(data), "bytes": data.count]
        }
        let project: [String: Any] = ["format": "open-screenplay-project", "format_version": "0.1-draft", "project_id": UUID().uuidString,
                                      "screenplay_id": id, "head": ["id": UUID().uuidString, "files": inventory]]
        try JSONSerialization.data(withJSONObject: project).write(to: root.appendingPathComponent("project.json"))
        let original = Data("{}".utf8)
        try original.write(to: root.appendingPathComponent("provenance/source.json"))
        try JSONSerialization.data(withJSONObject: ["candidate_version": "0.1", "source_sha256": digest(original)]).write(to: root.appendingPathComponent("provenance/candidate.json"))
        return root
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func snapshot(_ root: URL) throws -> [String: Data] {
        let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [String: Data] = [:]
        for case let url as URL in paths where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path] = try Data(contentsOf: url)
        }
        return result
    }
    @Test func readerPreservesExactTextAndNeverWrites() throws {
        let root = try makePackage(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try snapshot(root)
        let preview = try PackagePreviewReader.read(root)
        #expect(preview.scenes.count == 1)
        #expect(preview.paragraphs.count == 3)
        #expect(preview.paragraphs[1].type == "future_type")
        #expect(preview.paragraphs[1].text == "e\u{301} 👩🏽‍🚀\nExact text")
        #expect(preview.paragraphs[2].text.isEmpty)
        #expect(try snapshot(root) == before)
    }
    @Test func openingAndClosingPreviewDoesNotReplaceEditableDocument() throws {
        let root = try makePackage(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let suite = "PackagePreviewTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: workspace, preferences: preferences)
        model.newDocument()
        #expect(model.document != nil)
        let document = model.document, saveURL = model.saveURL, sourceURL = model.sourceURL
        model.openDocument(at: root)
        #expect(model.packagePreview != nil)
        #expect(model.document == document && model.saveURL == saveURL && model.sourceURL == sourceURL)
        model.packagePreview = nil
        #expect(model.document == document && model.saveURL == saveURL)
    }
    @Test func changedPayloadIsRejectedWithoutReplacingDocument() throws {
        let root = try makePackage(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("screenplay.json")
        var data = try Data(contentsOf: url); data.append(32); try data.write(to: url)
        #expect(throws: (any Error).self) { try PackagePreviewReader.read(root) }
        let model = ScreenplayViewModel(loadInitialDocument: false)
        model.openDocument(at: root)
        #expect(model.packagePreview == nil && model.errorMessage != nil && model.document == nil)
    }
    @Test func duplicateKeysUnsupportedVersionAndSymlinkAreRejected() throws {
        let root = try makePackage(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project.json")
        let original = try Data(contentsOf: project)
        var duplicate = Data("{\"duplicate\":1,\"duplica\\u0074e\":2,".utf8)
        duplicate.append(original.dropFirst())
        try duplicate.write(to: project)
        #expect(throws: (any Error).self) { try PackagePreviewReader.read(root) }
        let unsupported = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "0.1-draft", with: "9.0")
        try Data(unsupported.utf8).write(to: project)
        #expect(throws: (any Error).self) { try PackagePreviewReader.read(root) }
        try original.write(to: project)
        let source = root.appendingPathComponent("provenance/source.json")
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: project)
        #expect(throws: (any Error).self) { try PackagePreviewReader.read(root) }
    }
}
