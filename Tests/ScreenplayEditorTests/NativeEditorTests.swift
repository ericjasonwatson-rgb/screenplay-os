import AppKit
import SwiftUI
import Testing
@testable import ScreenplayOSApp

@Suite("Native editor rendering", .serialized)
@MainActor
struct NativeEditorTests {
    @Test func nativeTypingSelectionFormattingAndUndoRemainConsistent() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "NativeEditorTests.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                 with: "INT. ROOM - DAY\nFirst action.\nLast action.")
        let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func refresh() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        refresh()
        let view = try #require(find(host))
        let original = model.writingText
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText(" 👩🏽‍🚀", replacementRange: view.selectedRange())
        refresh()
        #expect(view.string == model.writingText)
        #expect(view.string == original + " 👩🏽‍🚀")
        #expect(view.selectedRange().location == (view.string as NSString).length)
        model.undo()
        refresh()
        #expect(view.string == original)
        model.redo()
        refresh()
        #expect(view.string == original + " 👩🏽‍🚀")
        let last = try #require(model.elements.last)
        model.setType(.dialogue, for: last.id)
        refresh()
        let range = try #require(model.writingRanges.last)
        let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(Double(style.headIndent) - 72 * model.pageZoom) < 0.001)
        let selection = NSRange(location: 0, length: 10)
        view.setSelectedRange(selection)
        model.contextAssistantVisible.toggle()
        refresh()
        #expect(view.selectedRange() == selection)
        model.pageZoom = 1.2
        refresh()
        let zoomStyle = try #require(view.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(zoomStyle.headIndent - 86.4) < 0.001)
    }
}
