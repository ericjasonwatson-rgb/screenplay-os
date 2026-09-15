import Foundation
import Testing
import ScreenplayDomain

@Suite("Package text command boundary")
struct PackageTextSessionTests {
    let first = UUID(), second = UUID(), document = UUID()
    func fixture() throws -> [String: Data] {
        let manifest = ["format": "open-screenplay", "format_version": "1.0", "document_id": document.uuidString,
                        "title": "Test", "author": "", "created_at": "2026-09-14T00:00:00Z", "modified_at": "2026-09-14T00:00:00Z"]
        let script: [String: Any] = ["id": document.uuidString, "elements": [
            ["id": second.uuidString, "type": "action", "text": "second"],
            ["id": first.uuidString, "type": "action", "text": "first"]]]
        return try ["manifest.json": JSONSerialization.data(withJSONObject: manifest), "screenplay.json": JSONSerialization.data(withJSONObject: script)]
    }
    @Test func identityNotOrderAndExactUndo() throws {
        let files = try fixture()
        var session = try PackageTextSession(files: files)
        let revision = session.revision
        try session.replaceText(elementID: first, expectedRevision: revision, expectedText: "first", replacement: "e\u{301} 👩🏽‍🚀\n")
        #expect(try session.text(for: second) == "second")
        #expect(try session.text(for: first) == "e\u{301} 👩🏽‍🚀\n")
        let edited = session.screenplayBytes
        session.undo()
        #expect(session.screenplayBytes == files["screenplay.json"])
        #expect(session.revision != revision)
        session.redo()
        #expect(session.screenplayBytes == edited)
        #expect(session.originalFiles == files)
    }
    @Test func staleMissingAndNoopAreAtomic() throws {
        var session = try PackageTextSession(files: fixture())
        let oldRevision = session.revision
        try session.replaceText(elementID: first, expectedRevision: oldRevision, expectedText: "first", replacement: "first")
        #expect(session.revision == oldRevision && !session.canUndo)
        try session.replaceText(elementID: first, expectedRevision: oldRevision, expectedText: "first", replacement: "changed")
        let before = session.screenplayBytes
        #expect(throws: PackageTextSession.Failure.self) {
            try session.replaceText(elementID: second, expectedRevision: oldRevision, expectedText: "second", replacement: "wrong")
        }
        #expect(throws: PackageTextSession.Failure.self) {
            try session.replaceText(elementID: UUID(), expectedRevision: session.revision, expectedText: "", replacement: "wrong")
        }
        #expect(session.screenplayBytes == before)
        session.undo()
        #expect(throws: PackageTextSession.Failure.self) {
            try session.replaceText(elementID: first, expectedRevision: oldRevision, expectedText: "first", replacement: "wrong")
        }
    }
    @Test func blocksAllUnadaptedCompanions() throws {
        for name in ["project.json", "extensions.json", "notes.json", "shots.json", "settings.json", "film/edit.json", "unknown.bin"] {
            var files = try fixture(); files[name] = Data("{}".utf8)
            #expect(throws: PackageTextSession.Failure.self) { _ = try PackageTextSession(files: files) }
        }
    }
    @Test func rejectsWrongVersionIdentityAndStaleText() throws {
        for (field, value) in [("format_version", "2.0"), ("document_id", UUID().uuidString)] {
            var files = try fixture()
            var metadata = try JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: String]
            metadata[field] = value
            files["manifest.json"] = try JSONSerialization.data(withJSONObject: metadata)
            #expect(throws: (any Error).self) { _ = try PackageTextSession(files: files) }
        }
        var session = try PackageTextSession(files: fixture())
        let before = session.screenplayBytes, revision = session.revision
        #expect(throws: PackageTextSession.Failure.self) {
            try session.replaceText(elementID: first, expectedRevision: revision, expectedText: "stale", replacement: "wrong")
        }
        #expect(session.screenplayBytes == before && session.revision == revision && !session.canUndo)
    }
    @Test func blocksRichElementsUnknownTypesAndDuplicateIDs() throws {
        for field in ["scene", "revision", "page_locks", "future"] {
            var files = try fixture()
            var root = try JSONSerialization.jsonObject(with: files["screenplay.json"]!) as! [String: Any]
            var elements = root["elements"] as! [[String: Any]]
            elements[0][field] = [] as [String]; root["elements"] = elements
            files["screenplay.json"] = try JSONSerialization.data(withJSONObject: root)
            #expect(throws: PackageTextSession.Failure.self) { _ = try PackageTextSession(files: files) }
        }
        for replacement in ["future_type", "page_break"] {
            var files = try fixture()
            files["screenplay.json"] = Data(String(decoding: files["screenplay.json"]!, as: UTF8.self).replacingOccurrences(of: "action", with: replacement).utf8)
            #expect(throws: PackageTextSession.Failure.self) { _ = try PackageTextSession(files: files) }
        }
        var files = try fixture()
        files["screenplay.json"] = Data(String(decoding: files["screenplay.json"]!, as: UTF8.self).replacingOccurrences(of: second.uuidString, with: first.uuidString.lowercased()).utf8)
        #expect(throws: PackageTextSession.Failure.self) { _ = try PackageTextSession(files: files) }
    }
}
