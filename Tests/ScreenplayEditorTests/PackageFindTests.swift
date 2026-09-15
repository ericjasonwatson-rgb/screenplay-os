import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package find and replace", .serialized) @MainActor
struct PackageFindTests {
    @Test func replacesAcrossParagraphsInOneExactUndoTransaction() throws {
        var session = try PackageDialoguePrintTests().fixture([("character", "ELI"), ("dialogue", "Eli meets ELI."), ("action", "Eli leaves.")])
        let original = session.screenplayBytes, ids = session.paragraphs.map(\.id)
        #expect(session.find("ELI", caseSensitive: true).count == 2)
        let matches = session.find("eli")
        #expect(matches.count == 4)
        try session.replaceMatches(matches, expectedRevision: session.revision, replacement: "MARA")
        let changed = session.screenplayBytes
        #expect(session.find("MARA").count == 4 && session.paragraphs.map(\.id) == ids)
        session.undo(); #expect(session.screenplayBytes == original && !session.canUndo)
        session.redo(); #expect(session.screenplayBytes == changed)
    }
    @Test func unicodeEmptyNoOpAndStaleRequestsAreSafe() throws {
        var session = try PackageDialoguePrintTests().fixture([("action", "é e\u{301} 👩🏽‍🚀"), ("dialogue", "next")])
        #expect(session.find("👩").isEmpty)
        #expect(session.find("👩🏽‍🚀").count == 1)
        #expect(session.find("").isEmpty && session.find("🚀\nnext").isEmpty)
        let original = session.screenplayBytes
        let emoji = session.find("👩🏽‍🚀")
        try session.replaceMatches(emoji, expectedRevision: session.revision, replacement: "👩🏽‍🚀")
        #expect(session.screenplayBytes == original && !session.canUndo)
        let revision = session.revision
        try session.replaceMatches(emoji, expectedRevision: revision, replacement: "")
        let deleted = session.screenplayBytes
        do {
            try session.replaceMatches(emoji, expectedRevision: revision, replacement: "stale")
            Issue.record("Stale revision accepted")
        } catch { #expect(session.screenplayBytes == deleted) }
        session.undo(); #expect(session.screenplayBytes == original)
        let accents = session.find("é")
        #expect(accents.count == 2)
        try session.replaceMatches(accents, expectedRevision: session.revision, replacement: "o")
        #expect(try session.text(for: session.paragraphs[0].id) == "o o 👩🏽‍🚀")
    }
    @Test func navigationWrapsAndReplaceRequiresSelectedMatch() throws {
        let (root, editor, text, c) = try PackageWritingAssistTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        editor.showFind(); editor.findQuery = "eli"; editor.replacementText = "MARA"
        let original = editor.session.screenplayBytes
        editor.replaceFound(all: false)
        #expect(editor.session.screenplayBytes == original)
        editor.navigateFind(); c.render(text)
        #expect(text.selectedRange() == editor.findMatches[0].range)
        editor.navigateFind(backward: true); c.render(text)
        #expect(text.selectedRange() == editor.findMatches.last?.range)
        editor.navigateFind(); c.render(text)
        editor.replaceFound(all: false); c.render(text)
        #expect(try editor.session.text(for: editor.rows[0].id) == "MARA")
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == original && text.selectedRange() == editor.findMatches[0].range)
        editor.replaceFound(all: true); c.render(text)
        let changed = editor.session.screenplayBytes
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == original)
        editor.redo(); c.render(text)
        #expect(editor.session.screenplayBytes == changed)
        let output = root.appendingPathComponent("Replaced.screenplay")
        #expect(editor.save(to: output))
        #expect(try PackageEditedCopy.load(output).screenplayBytes == changed)
        #expect(try Data(contentsOf: editor.source.appendingPathComponent("screenplay.json")) == original)
    }
}
