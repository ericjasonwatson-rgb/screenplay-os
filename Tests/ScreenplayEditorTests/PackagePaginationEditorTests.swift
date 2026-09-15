import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Paginated native writing", .serialized) @MainActor
struct PackagePaginationEditorTests {
    @Test func pagePositionsSelectionTypingAndUndoMatchPrint() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var session = try PackageEditedCopy.load(source)
        let speech = (0..<600).map { "word\($0)" }.joined(separator: " ")
        try session.changeType(elementID: session.paragraphs[0].id, expectedRevision: session.revision, type: "character")
        try session.changeType(elementID: id, expectedRevision: session.revision, type: "dialogue")
        try session.replaceText(elementID: id, expectedRevision: session.revision, expectedText: "first", replacement: speech)
        try session.screenplayBytes.write(to: source.appendingPathComponent("screenplay.json"))
        let editor = try PackageEditor(source: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let host = NSHostingView(rootView: PackageParagraphTextView(editor: editor))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        func find(_ v: NSView) -> PackageWritingNativeTextView? { (v as? PackageWritingNativeTextView) ?? v.subviews.lazy.compactMap { find($0) }.first }
        refresh()
        let text = try #require(find(host))
        let original = editor.session.screenplayBytes
        let plan = try #require(text.pagePlan)
        #expect(text.pageCount > 1 && plan.headers[1] != nil)
        let manager = try #require(text.layoutManager)
        for page in plan.ranges.indices {
            let character = plan.ranges[page].location
            let glyph = manager.glyphIndexForCharacter(at: character)
            let actual = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let expected = plan.layout.lineFragmentRect(forGlyphAt: plan.glyphRanges[page].location, effectiveRange: nil)
            #expect(abs(actual.minY - (expected.minY + CGFloat(page) * text.pageStride + plan.headerHeights[page])) < 0.01)
            let point = NSPoint(x: text.textContainerOrigin.x + actual.minX + 1, y: text.textContainerOrigin.y + actual.midY)
            let hit = text.characterIndexForInsertion(at: point)
            #expect(hit >= character && hit <= NSMaxRange(plan.ranges[page]))
        }
        let boundary = plan.ranges[1].location
        let spanning = NSRange(location: boundary - 4, length: 8)
        text.setSelectedRange(spanning)
        #expect(text.selectedRange() == spanning)
        text.insertText("EDIT", replacementRange: spanning); refresh()
        #expect(text.selectedRange().location == spanning.location + 4)
        #expect(text.string == PackageWritingProjection(editor.session).text)
        #expect(!text.string.contains("(MORE)") && !text.string.contains("(CONT’D)"))
        editor.undo(); refresh()
        #expect(editor.session.screenplayBytes == original)
        #expect(text.selectedRange() == spanning)
        editor.redo(); refresh()
        #expect(text.string.contains("EDIT"))
        #expect(editor.saveCurrent())
        #expect(try PackageEditedCopy.load(source).screenplayBytes == editor.session.screenplayBytes)
    }
    @Test func emptyPageDrawsInBothThemes() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var session = try PackageEditedCopy.load(source)
        for paragraph in session.paragraphs { try session.delete(elementID: paragraph.id, expectedRevision: session.revision) }
        _ = try session.insert(after: nil, expectedRevision: session.revision, type: "action", text: "")
        let native = PackageWritingNativeTextView(frame: .zero)
        native.textContainer?.widthTracksTextView = false
        native.textContainer?.containerSize = NSSize(width: 432, height: CGFloat.greatestFiniteMagnitude)
        native.textContainer?.lineFragmentPadding = 0
        try native.paginate(session)
        #expect(native.pageCount == 1)
        #expect(native.frame.height >= 792)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 612, pixelsHigh: 792, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for dark in [false, true] {
            native.darkPage = dark; native.backgroundColor = StudioAppearance.paper(dark)
            native.drawBackground(in: native.bounds)
        }
    }
}
