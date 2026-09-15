import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package writing assists", .serialized)
@MainActor
struct PackageWritingAssistTests {
    func fixture() throws -> (URL, PackageEditor, NSTextView, PackageParagraphTextView.Coordinator) {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        let base = PackageTextSessionTests()
        var files = try base.fixture()
        files["screenplay.json"] = try JSONSerialization.data(withJSONObject: ["id": base.document.uuidString,
            "elements": [("character", "ELI"), ("dialogue", "Hello."), ("character", "ELISE"), ("character", "eli"), ("action", "ELIZA"), ("character", "")].map {
                ["id": UUID().uuidString, "type": $0.0, "text": $0.1]
            }])
        for (name, data) in files { try data.write(to: source.appendingPathComponent(name)) }
        let editor = try PackageEditor(source: source)
        let text = NSTextView()
        let coordinator = PackageParagraphTextView.Coordinator(editor)
        text.delegate = coordinator
        coordinator.render(text)
        let last = PackageWritingProjection(editor.session).entries.last!
        text.setSelectedRange(NSRange(location: last.range.location, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        return (root, editor, text, coordinator)
    }
    @Test func cyclesTypesWithoutChangingTextIdentityOrSelection() throws {
        let (root, editor, text, c) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = editor.session.screenplayBytes, ids = editor.rows.map(\.id), range = text.selectedRange()
        #expect(c.textView(text, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(editor.rows.last?.type == "dialogue")
        #expect(text.selectedRange() == range && editor.rows.map(\.id) == ids)
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == before)
        editor.redo(); c.render(text)
        #expect(editor.rows.last?.type == "dialogue")
        #expect(c.textView(text, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(editor.rows.last?.type == "character")
        for _ in PackageTextSession.supportedTypes { _ = c.textView(text, doCommandBy: #selector(NSResponder.insertBacktab(_:))) }
        #expect(editor.rows.last?.type == "character")
        text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
        let revision = editor.session.revision
        _ = c.textView(text, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(editor.session.revision == revision)
    }
    @Test func suggestionsRequireExplicitAcceptanceAndPersistWithUndo() throws {
        let (root, editor, text, c) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = editor.session.screenplayBytes
        text.insertText("El", replacementRange: text.selectedRange())
        #expect(editor.characterSuggestions == ["ELI", "ELISE"])
        let typed = editor.session.screenplayBytes
        _ = c.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(editor.characterSuggestions.isEmpty && editor.session.screenplayBytes == typed)
        c.updateSuggestions(text)
        #expect(editor.characterSuggestions.isEmpty)
        text.insertText("i", replacementRange: text.selectedRange())
        #expect(editor.characterSuggestions == ["ELISE"])
        let prefix = editor.session.screenplayBytes
        _ = c.textView(text, doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = c.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(editor.draft == "ELISE" && editor.rows.count == 6)
        #expect(text.selectedRange().location == (text.string as NSString).length)
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == prefix)
        editor.redo(); c.render(text)
        let copy = root.appendingPathComponent("Assisted.screenplay")
        #expect(editor.save(to: copy))
        #expect(try PackageEditedCopy.load(copy).screenplayBytes == editor.session.screenplayBytes)
        #expect(try Data(contentsOf: editor.source.appendingPathComponent("screenplay.json")) == original)
    }
    @Test func returnWithoutHighlightStillCreatesDialogueAndCaretMovementHidesSuggestions() throws {
        let (root, editor, text, c) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        text.insertText("E", replacementRange: text.selectedRange())
        #expect(!editor.characterSuggestions.isEmpty)
        _ = c.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(editor.rows.last?.type == "dialogue" && editor.rows.count == 7)
        #expect(try editor.session.text(for: editor.rows[5].id) == "E")
        #expect(editor.characterSuggestions.isEmpty)
        editor.undo(); c.render(text)
        text.setSelectedRange(NSRange(location: 0, length: 1))
        c.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(editor.characterSuggestions.isEmpty)
    }
}
