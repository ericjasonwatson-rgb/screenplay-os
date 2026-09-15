import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package writing history", .serialized)
@MainActor
struct PackageHistoryTests {
    @Test func completionRedoRestoresEndCaret() throws {
        let (root, editor, text, c) = try PackageWritingAssistTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        text.insertText("Eli", replacementRange: text.selectedRange())
        _ = c.textView(text, doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = c.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.undo(); c.render(text)
        #expect(editor.draft == "Eli")
        editor.redo(); c.render(text)
        #expect(text.selectedRange() == NSRange(location: (text.string as NSString).length, length: 0))
        text.insertText("X", replacementRange: text.selectedRange())
        #expect(editor.draft == "ELISEX")
    }
    @Test func typingAndBackwardDeletionHaveSeparateGroups() throws {
        let (root, editor, text, c) = try PackageWritingAssistTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = editor.session.screenplayBytes, start = text.selectedRange()
        for letter in ["a", "b", "c"] { text.insertText(letter, replacementRange: text.selectedRange()) }
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == original && text.selectedRange() == start)
        editor.redo(); c.render(text)
        #expect(editor.draft == "abc")
        for _ in 0..<3 { text.deleteBackward(nil) }
        #expect(editor.draft.isEmpty)
        editor.undo(); c.render(text)
        #expect(editor.draft == "abc")
        #expect(text.selectedRange().location == (text.string as NSString).length)
    }
    @Test func selectionSplitPauseAndSaveAreHistoryBoundaries() throws {
        let (root, editor, text, c) = try PackageWritingAssistTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        text.insertText("é👩🏽‍🚀", replacementRange: text.selectedRange())
        let end = (text.string as NSString).length
        let selection = NSRange(location: end - ("👩🏽‍🚀" as NSString).length, length: ("👩🏽‍🚀" as NSString).length)
        text.setSelectedRange(selection)
        text.insertText("X", replacementRange: text.selectedRange())
        editor.undo(); c.render(text)
        #expect(text.selectedRange() == selection)
        editor.redo(); c.render(text)
        #expect(editor.draft == "éX" && text.selectedRange().length == 0)
        _ = c.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        let split = editor.session.screenplayBytes, splitCaret = text.selectedRange()
        editor.undo(); c.render(text); editor.redo(); c.render(text)
        #expect(editor.session.screenplayBytes == split && text.selectedRange() == splitCaret)
        text.insertText("a", replacementRange: text.selectedRange())
        c.typingGroup?.time -= 2
        text.insertText("b", replacementRange: text.selectedRange())
        editor.undo(); c.render(text)
        #expect(editor.draft == "a")
        editor.redo(); c.render(text)
        let destination = root.appendingPathComponent("History.screenplay")
        #expect(editor.save(to: destination))
        let saved = editor.session.screenplayBytes
        text.insertText("c", replacementRange: text.selectedRange())
        editor.undo(); c.render(text)
        #expect(editor.session.screenplayBytes == saved)
        #expect(try PackageEditedCopy.load(destination).screenplayBytes == saved)
    }
    @Test func groupedEditsRecoverLatestTextWithoutPersistingHistory() throws {
        let (root, initial, _, _) = try PackageWritingAssistTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: initial.source, recoveryDirectory: directory)
        let id = editor.rows.last!.id
        editor.selectWritingParagraph(id)
        let group = UUID()
        for prefix in ["a", "ab", "abc"] {
            #expect(editor.editWritingSpan(start: id, end: id, prefix: "", replacement: prefix, suffix: "", splitType: nil, historyGroup: group))
        }
        #expect(editor.flushRecovery())
        let record = try #require(PackageRecovery.list(directory).first)
        let restored = try PackageEditor(recovery: record, directory: directory)
        #expect(restored.session.screenplayBytes == editor.session.screenplayBytes)
        #expect(!restored.canUndo)
        editor.undo()
        #expect(try editor.session.text(for: id) == "")
    }
    @Test func historyStepLimitAndBranchingPreserveExactBytes() throws {
        let original = Data("{ \"value\" : \"0\" }".utf8)
        var session = try PreservedJSONSession(original)
        for i in 1...250 { try session.replaceString(at: [.key("value")], expected: String(i-1), with: String(i)) }
        #expect(session.historyIDs.count == 200)
        for _ in 0..<200 { session.undo() }
        #expect(!session.canUndo && session.document.data == Data("{ \"value\" : \"50\" }".utf8))
        for _ in 0..<200 { session.redo() }
        #expect(session.document.data == Data("{ \"value\" : \"250\" }".utf8))
        session.undo()
        try session.replaceString(at: [.key("value")], expected: "249", with: "branch")
        #expect(!session.canRedo && session.historyIDs.count <= 200)
    }
    @Test func sustainedLargeDocumentHistoryStaysWithinByteBudget() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["body": String(repeating: "a", count: 1_048_576), "value": "0"])
        var session = try PreservedJSONSession(data)
        for i in 1...70 {
            try session.replaceString(at: [.key("value")], expected: String(i-1), with: String(i))
            #expect(session.historyBytes <= PreservedJSONSession.maximumHistoryBytes)
            await Task.yield()
        }
        #expect(session.historyIDs.count < 70 && session.canUndo)
        let latest = session.document.data
        session.undo(); session.redo()
        #expect(session.document.data == latest && session.historyBytes <= PreservedJSONSession.maximumHistoryBytes)
    }
}
