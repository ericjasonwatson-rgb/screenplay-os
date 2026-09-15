import AppKit
import SwiftUI
import Testing
@testable import ScreenplayOSApp

@Suite("Package page zoom", .serialized) @MainActor
struct PackagePageZoomTests {
    @Test func scalingPreservesLayoutSelectionAndDocument() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let original = editor.session.screenplayBytes, revision = editor.session.revision
        let host = NSHostingView(rootView: PackageParagraphTextView(editor: editor))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        func find(_ v: NSView) -> PackageWritingScrollView? {
            (v as? PackageWritingScrollView) ?? v.subviews.lazy.compactMap { find($0) }.first
        }
        refresh()
        let scroll = try #require(find(host)), text = try #require(scroll.documentView as? PackageWritingNativeTextView)
        let pages = try #require(text.pagePlan).ranges
        text.setSelectedRange(NSRange(location: 1, length: 2))
        for percent in [50, 150, 300, 100, 0] {
            host.rootView = PackageParagraphTextView(editor: editor, zoomPercent: percent)
            refresh()
            for width in [700.0, 420.0] {
                window.setContentSize(NSSize(width: width, height: 600)); refresh()
                let expected = percent == 0 ? scroll.contentView.frame.width / 612 : CGFloat(percent) / 100
                #expect(abs(scroll.magnification - expected) < 0.001)
                #expect(text.frame.width == 612 && text.textContainer?.containerSize.width == 432)
                #expect(text.pagePlan?.ranges == pages)
                #expect(text.selectedRange() == NSRange(location: 1, length: 2))
                #expect(editor.session.revision == revision && editor.session.screenplayBytes == original)
                #expect(!editor.dirty && !editor.canUndo)
                let a = text.convert(NSPoint(x: 108, y: 72), to: nil)
                let b = text.convert(NSPoint(x: 208, y: 72), to: nil)
                #expect(abs((b.x - a.x) - expected * 100) < 0.01)
            }
        }
        host.rootView = PackageParagraphTextView(editor: editor, zoomPercent: 150); refresh()
        text.insertText("café 👩🏽‍🚀", replacementRange: text.selectedRange()); refresh()
        #expect(text.string == PackageWritingProjection(editor.session).text)
        editor.undo(); refresh()
        #expect(editor.session.screenplayBytes == original)
        #expect(text.pagePlan?.ranges == pages)
        #expect(scroll.magnification == 1.5)
        let printed = try PackagePrintLayout.make(editor.session)
        #expect(printed.characterRanges == pages)
    }
}
