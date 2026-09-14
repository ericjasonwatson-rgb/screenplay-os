import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Continuous package writing", .serialized)
@MainActor
struct PackageContinuousTests {
    @Test func nativeSelectionMergeUndoAndPersistence() throws {
        _ = NSApplication.shared
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: store)
        let original = editor.session.screenplayBytes
        let ids = editor.rows.map(\.id)
        let host = NSHostingView(rootView: PackageParagraphTextView(editor: editor))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        refresh()
        let text = try #require(find(host))
        // Repeated delimiters are textually ambiguous: native edit ranges must win.
        editor.select(ids[0]); editor.addParagraph(); refresh()
        let emptyID = try #require(editor.selected)
        let blankProjection = PackageWritingProjection(editor.session)
        let blank = try #require(blankProjection.entries.first(where: { $0.id == emptyID }))
        text.setSelectedRange(NSRange(location: blank.range.location, length: 0))
        text.deleteBackward(nil); refresh()
        #expect(editor.rows.map(\.id) == ids)
        #expect(editor.selected == ids[0])
        editor.undo(); refresh(); editor.undo(); refresh()
        #expect(editor.session.screenplayBytes == original)
        let projection = PackageWritingProjection(editor.session)
        #expect(text.string == projection.text)
        let second = projection.entries[1]
        text.setSelectedRange(NSRange(location: second.range.location, length: 0))
        text.deleteBackward(nil); refresh()
        #expect(editor.rows.count == ids.count - 1)
        #expect(editor.rows[0].id == ids[0])
        #expect(try editor.session.text(for: ids[0]) == projection.entries[0].text + second.text)
        editor.undo(); refresh()
        #expect(editor.session.screenplayBytes == original)
        editor.redo(); refresh()
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        text.insertText(" e\u{301} 👩🏽‍🚀", replacementRange: text.selectedRange()); refresh()
        #expect(text.string == PackageWritingProjection(editor.session).text)
        #expect(text.string.hasSuffix(" e\u{301} 👩🏽‍🚀"))
        editor.flushRecovery()
        let record = try #require(PackageRecovery.list(store).first)
        let restored = try PackageEditor(recovery: record, directory: store)
        #expect(restored.session.screenplayBytes == editor.session.screenplayBytes)
        let output = root.appendingPathComponent("Continuous.screenplay")
        #expect(restored.save(to: output))
        #expect(try PackageEditedCopy.load(output).screenplayBytes == editor.session.screenplayBytes)
        #expect(try Data(contentsOf: source.appendingPathComponent("screenplay.json")) == original)
    }
    @Test func spanningReplacementAndSplitAreAtomic() throws {
        let fixture = PackageTextSessionTests()
        var session = try PackageTextSession(files: fixture.fixture())
        let before = session.screenplayBytes
        let id = try session.editSpan(startID: fixture.second, endID: fixture.first, expectedRevision: session.revision,
                                     prefix: "sec", replacement: "X", suffix: "st", splitType: "dialogue")
        #expect(session.paragraphs.map(\.id) == [fixture.second, id])
        #expect(try session.text(for: fixture.second) == "secX")
        #expect(try session.text(for: id) == "st")
        session.undo(); #expect(session.screenplayBytes == before)
        session.redo(); #expect(session.paragraphs.last?.id == id)
        let current = session.screenplayBytes
        #expect(throws: PackageTextSession.Failure.self) {
            try session.editSpan(startID: id, endID: fixture.second, expectedRevision: session.revision, prefix: "", replacement: "", suffix: "")
        }
        #expect(session.screenplayBytes == current)
    }
}
