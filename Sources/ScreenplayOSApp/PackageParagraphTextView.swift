import AppKit
import SwiftUI

/// Native input adapter: IME and paste stay text; unmodified Return is a command.
struct PackageParagraphTextView: NSViewRepresentable {
    @ObservedObject var editor: PackageEditor
    func makeCoordinator() -> Coordinator { Coordinator(editor) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.allowsUndo = false // The package command history owns undo across paragraphs.
        text.setAccessibilityLabel("Paragraph text")
        text.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        let changedSelection = context.coordinator.selected != editor.selected
        context.coordinator.editor = editor
        context.coordinator.selected = editor.selected
        if !text.hasMarkedText(), !text.string.unicodeScalars.elementsEqual(editor.draft.unicodeScalars) {
            let range = text.selectedRange()
            text.string = editor.draft
            text.setSelectedRange(NSRange(location: min(range.location, (text.string as NSString).length), length: 0))
        }
        if changedSelection {
            text.setSelectedRange(NSRange(location: 0, length: 0))
            DispatchQueue.main.async { [weak text] in
                guard let text else { return }; text.window?.makeFirstResponder(text)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: PackageEditor
        var selected: UUID?
        init(_ editor: PackageEditor) { self.editor = editor }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            editor.draft = text.string
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) { return false }
            editor.draft = textView.string
            _ = editor.splitParagraph(at: textView.selectedRange())
            return true
        }
    }
}
