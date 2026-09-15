import AppKit
import PDFKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package formatting integration", .serialized) @MainActor
struct PackageFormattingTests {
    func fixture() throws -> (URL, URL, UUID) {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        var session = try PackageEditedCopy.load(source)
        try session.format(elementID: id, expectedRevision: session.revision, range: 0..<5,
                           patch: .init(bold: true, italic: true, underline: true, strikethrough: true))
        try session.screenplayBytes.write(to: source.appendingPathComponent("screenplay.json"))
        try Data("{ \"formatting\": {\"paper\":\"US_LETTER\",\"font_family\":\"Courier\",\"font_size\":16} }\n".utf8)
            .write(to: source.appendingPathComponent("settings.json"))
        return (root, source, id)
    }
    @Test func styledEditsSplitJoinAndExactUndo() throws {
        let (root, source, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var session = try PackageEditedCopy.load(source)
        let original = session.screenplayBytes
        try session.replaceText(elementID: id, expectedRevision: session.revision, expectedText: "first", replacement: "fi👩🏽‍🚀rst")
        #expect(try session.styledText(for: id).resolvedRuns.allSatisfy { $0.style.bold == true })
        let edited = session.screenplayBytes
        try session.replaceMatches(session.find("rst"), expectedRevision: session.revision, replacement: "REST")
        #expect(try session.styledText(for: id).resolvedRuns.first?.style.italic == true)
        session.undo(); #expect(session.screenplayBytes == edited)
        let next = try session.split(elementID: id, expectedRevision: session.revision, prefix: "fi👩🏽‍🚀", suffix: "rst", nextType: "action")
        #expect(try session.styledText(for: next).resolvedRuns.first?.style.underline == true)
        session.undo(); #expect(session.screenplayBytes == edited)
        session.redo()
        _ = try session.editSpan(startID: id, endID: next, expectedRevision: session.revision, prefix: "fi👩🏽‍🚀", replacement: "", suffix: "rst")
        #expect(try session.text(for: id) == "fi👩🏽‍🚀rst")
        #expect(!session.paragraphs.contains { $0.id == next })
        session.undo(); session.undo(); session.undo()
        #expect(session.screenplayBytes == original)
        try session.format(elementID: id, expectedRevision: session.revision, range: 1..<3, patch: .init(bold: false))
        #expect(try session.styledText(for: id).resolvedRuns.contains { $0.style.bold != true && $0.style.italic == true })
        session.undo(); #expect(session.screenplayBytes == original)
    }
    @Test func savesRecoveryAndExternalSettingsConflict() throws {
        let (root, source, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try PackageEditedCopy.snapshot(source)
        let recovery = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: recovery)
        editor.select(id); editor.draft = "first!"
        #expect(editor.saveCurrent())
        #expect(try PackageEditedCopy.snapshot(editor.previousVersionURL!) == initial)
        #expect(try PackageEditedCopy.snapshot(source)["settings.json"] == initial["settings.json"])
        #expect(try PackageEditedCopy.load(source).styledText(for: id).resolvedRuns.first?.style.bold == true)
        editor.draft = "first!!"
        let outside = Data("{\"formatting\":{\"paper\":\"US_LETTER\",\"font_family\":\"Courier\",\"font_size\":18}}".utf8)
        try outside.write(to: source.appendingPathComponent("settings.json"))
        #expect(!editor.saveCurrent() && editor.dirty)
        #expect(try Data(contentsOf: source.appendingPathComponent("settings.json")) == outside)
        let record = try #require(PackageRecovery.list(recovery).first)
        #expect(record.files["settings.json"] == initial["settings.json"])
        #expect(try PackageTextSession(files: record.files).styledText(for: id).text == "first!!")
        let copy = root.appendingPathComponent("Copy.screenplay")
        #expect(editor.save(to: copy))
        #expect(try PackageEditedCopy.snapshot(copy)["settings.json"] == initial["settings.json"])
    }
    @Test func settingsWriteFailureRetainsOriginalAndRecovery() throws {
        let (root, source, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try PackageEditedCopy.snapshot(source)
        let recovery = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: recovery)
        editor.select(id); editor.draft = "first modified"
        #expect(!editor.saveCurrent { phase, _ in
            if phase == "write:settings.json" { throw PackageEditedCopyTests.Injected.stop }
        })
        #expect(editor.dirty)
        #expect(try PackageEditedCopy.snapshot(source) == original)
        #expect(PackageRecovery.list(recovery).first?.files["settings.json"] == original["settings.json"])
    }
    @Test func nativeTypingRestylesAndUndoRestoresEmphasis() throws {
        let (root, source, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let host = NSHostingView(rootView: PackageParagraphTextView(editor: editor))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap { find($0) }.first }
        refresh()
        let text = try #require(find(host))
        let range = (text.string as NSString).range(of: "first")
        editor.changeTypography(size: 24); refresh()
        let resized = try #require(text.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        #expect(abs(resized.pointSize - 28) < 0.01)
        editor.undo(); refresh()
        #expect(editor.session.typography.fontSize == 16)
        let original = editor.session.screenplayBytes
        text.setSelectedRange(NSRange(location: range.location + 2, length: 0))
        text.insertText("X", replacementRange: text.selectedRange()); refresh()
        #expect(try editor.session.text(for: id) == "fiXrst")
        let font = try #require(text.textStorage?.attribute(.font, at: range.location + 2, effectiveRange: nil) as? NSFont)
        #expect(abs(font.pointSize - 16 * 14.0 / 12.0) < 0.01)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(text.textStorage?.attribute(.underlineStyle, at: range.location + 2, effectiveRange: nil) as? Int == 1)
        editor.undo(); refresh()
        #expect(editor.session.screenplayBytes == original)
        #expect(text.string.contains("first"))
    }
    @Test func sharedRenderingAndStrictProjection() throws {
        let (root, source, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try PackageEditedCopy.load(source)
        let value = try session.styledText(for: id)
        let text = NSMutableAttributedString(string: value.text)
        PackageTypography.apply(value, settings: session.typography, to: text, offset: 0)
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 16)
        #expect(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
        #expect(text.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1)
        #expect(text.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int == 1)
        let pdf = try #require(PDFDocument(data: PackagePrintLayout.make(session).data))
        #expect(pdf.string?.contains("first") == true)
        let missing = try DocumentTypography(fontFamily: "NoSuchScreenplayFont-123")
        #expect(PackageTypography.substitution(missing) != nil)
        #expect(PackageTypography.font(missing).familyName == "Courier")
        var files = session.originalFiles
        files["settings.json"] = Data("{\"formatting\":{\"paper\":\"A4\",\"font_family\":\"Courier\",\"font_size\":12}}".utf8)
        #expect(throws: (any Error).self) { _ = try PackageTextSession(files: files) }
        files = session.originalFiles
        files["screenplay.json"] = Data(String(decoding: files["screenplay.json"]!, as: UTF8.self).replacingOccurrences(of: "\"bold\":true", with: "\"unknown\":true").utf8)
        #expect(throws: (any Error).self) { _ = try PackageTextSession(files: files) }
    }
}

@Suite("Typography document transactions", .serialized) @MainActor
struct TypographyTransactionTests {
    @Test func interleavedHistoryRestoresAbsentAndExactSettings() throws {
        let fixture = PackageTextSessionTests()
        let files = try fixture.fixture()
        var session = try PackageTextSession(files: files)
        try session.setTypography(try .init(fontFamily: "Helvetica", fontSize: 18), expectedRevision: session.revision)
        let settings = session.settingsBytes
        try session.replaceText(elementID: fixture.first, expectedRevision: session.revision, expectedText: "first", replacement: "changed")
        try session.setTypography(try .init(fontSize: 24), expectedRevision: session.revision)
        session.undo(); #expect(session.settingsBytes == settings && session.typography.fontSize == 18)
        session.undo(); #expect(try session.text(for: fixture.first) == "first")
        #expect(session.settingsBytes == settings)
        session.undo(); #expect(session.currentFiles == files && session.typography.fontSize == 12)
        session.redo(); session.redo(); session.redo()
        #expect(session.typography.fontSize == 24)
        #expect(try session.text(for: fixture.first) == "changed")
        let before = session.currentFiles
        #expect(throws: (any Error).self) { try session.setTypography(try .init(paper: "A4"), expectedRevision: session.revision) }
        #expect(session.currentFiles == before)
    }
    @Test func fontOnlySaveRecoveryUndoAndReopen() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: recovery)
        editor.changeTypography(font: "Helvetica", size: 18)
        #expect(editor.dirty)
        #expect(editor.flushRecovery())
        let record = try #require(PackageRecovery.list(recovery).first)
        #expect(try PackageTextSession(files: record.files).typography.fontSize == 18)
        #expect(editor.saveCurrent() && !editor.dirty)
        #expect(try PackageEditedCopy.load(source).typography.fontFamily == "Helvetica")
        editor.undo(); #expect(editor.dirty && editor.session.settingsBytes == nil)
        #expect(editor.saveCurrent() && !editor.dirty)
        #expect(try PackageEditedCopy.load(source).settingsBytes == nil)
        editor.redo(); #expect(editor.dirty && editor.session.typography.fontSize == 18)
        #expect(editor.save(to: root.appendingPathComponent("Font Copy.screenplay")))
        #expect(try PackageEditedCopy.load(root.appendingPathComponent("Font Copy.screenplay")).typography.fontSize == 18)
    }
    @Test func failedFontOnlySaveRetainsRecoveryAndOriginal() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: recovery)
        let before = try PackageEditedCopy.snapshot(source)
        editor.changeTypography(size: 18)
        #expect(!editor.saveCurrent { phase, _ in
            if phase == "write:settings.json" { throw PackageEditedCopyTests.Injected.stop }
        })
        #expect(editor.dirty)
        #expect(try PackageEditedCopy.snapshot(source) == before)
        let record = try #require(PackageRecovery.list(recovery).first)
        #expect(try PackageTextSession(files: record.files).typography.fontSize == 18)
    }
    @Test func selectionFormattingIsOneAtomicTransaction() throws {
        let fixture = PackageTextSessionTests()
        var session = try PackageTextSession(files: fixture.fixture())
        let before = session.screenplayBytes
        try session.formatSelection(NSRange(location: 3, length: 6), expectedRevision: session.revision, patch: .init(underline: true))
        #expect(try session.styledText(for: fixture.second).resolvedRuns.first?.start == 3)
        #expect(try session.styledText(for: fixture.first).resolvedRuns.first?.length == 2)
        session.undo(); #expect(session.screenplayBytes == before && !session.canUndo)
        session.redo(); #expect(session.screenplayBytes != before)
    }
}
