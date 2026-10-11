import Foundation
import ScreenplayDomain
import Testing
@testable import ScreenplayOSApp

@Suite("ScreenplayOS format rename")
@MainActor
struct FormatRenameTests {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    }

    private func environment(_ body: (URL, ScreenplayViewModel) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "FormatRenameTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            preferences.removePersistentDomain(forName: suite)
        }
        try body(root, ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: preferences))
    }

    @Test func oldDocumentOpensInPlaceAndAutosavesToItsOriginalPath() throws {
        try environment { root, model in
            let fixture = fixture("Defenders_of_Cat_Island.open-screenplay.json")
            let original = try Data(contentsOf: fixture)
            let url = root.appendingPathComponent("Legacy.open-screenplay.json")
            try original.write(to: url)
            model.loadScreenplayOSDocument(at: url)
            #expect(model.saveURL == url)
            #expect(model.errorMessage?.contains("opened as a copy") != true)
            let first = try #require(model.elements.first)
            model.editText(id: first.id, text: first.text + " ", before: .init(location: 0, length: 0),
                           after: .init(location: 0, length: 0), groupable: false)
            #expect(model.saveURL == url)
            #expect(FileManager.default.fileExists(atPath: url.path))
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect(json["format"] as? String == "screenplayos")
        }
    }

    @Test func newFormatFixtureDecodes() throws {
        let decoded = try JSONDecoder.screenplayOSDecoder().decode(
            ScreenplayOSDocument.self,
            from: Data(contentsOf: fixture("Minimal.screenplayos.json"))
        )
        #expect(decoded.format == "screenplayos")
        #expect(decoded.screenplay.elements.count == 2)
    }

    @Test func newDocumentUsesNewExtensionAndIdentifier() throws {
        try environment { _, model in
            model.newDocument()
            model.save()
            let url = try #require(model.saveURL)
            #expect(url.lastPathComponent.hasSuffix(".screenplayos.json"))
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect(json["format"] as? String == "screenplayos")
        }
    }

    @Test func packageReaderAcceptsOldManifestAndNewWriterMigratesIt() throws {
        try environment { root, _ in
            let package = root.appendingPathComponent("Legacy.screenplay")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let id = UUID(), paragraph = UUID(), time = "2026-10-11T00:00:00Z"
            let manifest: [String: Any] = ["format": "open-screenplay", "format_version": "1.0",
                "document_id": id.uuidString, "title": "Legacy", "author": "", "created_at": time, "modified_at": time]
            let screenplay: [String: Any] = ["id": id.uuidString,
                "elements": [["id": paragraph.uuidString, "type": "action", "text": "Old package"]]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: package.appendingPathComponent("manifest.json"))
            try JSONSerialization.data(withJSONObject: screenplay).write(to: package.appendingPathComponent("screenplay.json"))
            let session = try PackageEditedCopy.load(package)
            let output = root.appendingPathComponent("Migrated.screenplay")
            _ = try PackageEditedCopy.save(session, source: package, destination: output)
            let migrated = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("manifest.json"))) as? [String: Any])
            #expect(migrated["format"] as? String == "screenplayos")
        }
    }
}
