import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package structural commands")
struct PackageStructureTests {
    @Test func structuralHistoryAndStableTargets() throws {
        let fixture = PackageTextSessionTests()
        let files = try fixture.fixture()
        var session = try PackageTextSession(files: files)
        let original = session.screenplayBytes
        let oldRevision = session.revision
        let added = try session.insert(after: fixture.second, expectedRevision: session.revision, type: "character", text: "ÉLI")
        #expect(session.paragraphs.map(\.id) == [fixture.second, added, fixture.first])
        try session.changeType(elementID: fixture.first, expectedRevision: session.revision, type: "dialogue")
        try session.delete(elementID: fixture.second, expectedRevision: session.revision)
        #expect(try session.text(for: fixture.first) == "first")
        let changed = session.screenplayBytes
        #expect(throws: PackageTextSession.Failure.self) { try session.delete(elementID: fixture.first, expectedRevision: oldRevision) }
        #expect(session.screenplayBytes == changed)
        session.undo(); session.undo(); session.undo()
        #expect(session.screenplayBytes == original)
        session.redo(); session.redo(); session.redo()
        #expect(session.screenplayBytes == changed)
        #expect(session.paragraphs.map(\.id) == [added, fixture.first])
        #expect(session.originalFiles == files)
    }
    @Test func emptyAndRejectedCommands() throws {
        var session = try PackageTextSession(files: PackageTextSessionTests().fixture())
        for row in session.paragraphs { try session.delete(elementID: row.id, expectedRevision: session.revision) }
        #expect(session.paragraphs.isEmpty)
        let added = try session.insert(after: nil, expectedRevision: session.revision)
        let bytes = session.screenplayBytes
        #expect(throws: PackageTextSession.Failure.self) { try session.insert(after: nil, expectedRevision: session.revision, id: added) }
        #expect(throws: PackageTextSession.Failure.self) { try session.changeType(elementID: added, expectedRevision: session.revision, type: "page_break") }
        #expect(session.screenplayBytes == bytes)
        session.undo(); #expect(session.paragraphs.isEmpty)
        session.redo(); #expect(session.paragraphs.first?.id == added)
    }
}

@Suite("Package structural workflow")
@MainActor
struct PackageStructureWorkflowTests {
    @Test func splitUnicodeDeleteRecoverAndSave() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source.appendingPathComponent("screenplay.json"))
        let directory = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: directory)
        editor.select(id); editor.draft = "e\u{301} 👩🏽‍🚀 suffix"
        editor.changeType("character")
        let prefix = "e\u{301} 👩🏽‍🚀 "
        #expect(!editor.splitParagraph(at: NSRange(location: 1, length: 0)))
        #expect(editor.splitParagraph(at: NSRange(location: (prefix as NSString).length, length: 0)))
        let added = try #require(editor.selected)
        #expect(added != id && editor.draft == "suffix")
        #expect(editor.rows.first(where: { $0.id == added })?.type == "dialogue")
        #expect(try editor.session.text(for: id) == prefix)
        editor.undo(); #expect(editor.selected == id && editor.draft == prefix + "suffix")
        editor.redo(); #expect(editor.selected == added && editor.draft == "suffix")
        editor.deleteParagraph(); #expect(!editor.rows.contains(where: { $0.id == added }))
        editor.undo(); #expect(editor.selected == added && editor.draft == "suffix")
        editor.changeType("transition")
        editor.flushRecovery()
        let record = try #require(PackageRecovery.list(directory).first)
        let recovered = try PackageEditor(recovery: record, directory: directory)
        #expect(recovered.rows.map(\.id) == editor.rows.map(\.id))
        #expect(recovered.rows.first(where: { $0.id == added })?.type == "transition")
        let output = root.appendingPathComponent("Structure.screenplay")
        #expect(recovered.save(to: output))
        let reopened = try PackageEditor(source: output)
        #expect(try reopened.session.text(for: added) == "suffix")
        #expect(reopened.rows.map(\.id) == editor.rows.map(\.id))
        #expect(try Data(contentsOf: source.appendingPathComponent("screenplay.json")) == original)
    }
    @Test func deleteLastParagraphAndStartAgain() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source)
        while !editor.rows.isEmpty { editor.deleteParagraph() }
        #expect(editor.selected == nil && editor.draft.isEmpty)
        editor.addParagraph()
        #expect(editor.rows.count == 1 && editor.selected != nil)
        editor.undo(); #expect(editor.rows.isEmpty && editor.selected == nil)
        editor.undo(); #expect(editor.rows.count == 1 && editor.selected != nil)
    }
}
