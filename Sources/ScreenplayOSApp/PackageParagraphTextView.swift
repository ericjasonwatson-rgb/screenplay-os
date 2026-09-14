import AppKit
import SwiftUI
import ScreenplayDomain

/// Maps the continuous native text surface back to stable paragraph identities.
struct PackageWritingProjection {
    struct Entry { let id: UUID; let type: String; let range: NSRange; let text: String }
    let entries: [Entry]
    let text: String
    init(_ session: PackageTextSession) {
        var entries: [Entry] = [], text = ""
        for row in session.paragraphs {
            if !entries.isEmpty { text += "\n" }
            let value = (try? session.text(for: row.id)) ?? ""
            entries.append(Entry(id: row.id, type: row.type,
                                 range: NSRange(location: (text as NSString).length, length: (value as NSString).length), text: value))
            text += value
        }
        self.entries = entries; self.text = text
    }
    func position(_ offset: Int) -> (Entry, String.Index)? {
        guard offset >= 0 else { return nil }
        for entry in entries where offset >= entry.range.location && offset <= NSMaxRange(entry.range) {
            guard let range = Range(NSRange(location: offset - entry.range.location, length: 0), in: entry.text),
                  entry.text.indices.contains(range.lowerBound) || range.lowerBound == entry.text.endIndex else { return nil }
            return (entry, range.lowerBound)
        }
        return nil
    }
}

/// One native text view provides continuous selection, navigation, and copying.
struct PackageParagraphTextView: NSViewRepresentable {
    @ObservedObject var editor: PackageEditor
    func makeCoordinator() -> Coordinator { Coordinator(editor) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.allowsUndo = false
        text.textContainerInset = NSSize(width: 24, height: 24)
        text.setAccessibilityLabel("Screenplay text")
        text.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        context.coordinator.editor = editor
        guard !text.hasMarkedText() else { return }
        context.coordinator.render(text)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: PackageEditor
        var projection: PackageWritingProjection
        var rendering = false
        var renderedRevision: UUID?
        var selected: UUID?
        var nativeEdit: (NSRange, String)?
        init(_ editor: PackageEditor) { self.editor = editor; projection = PackageWritingProjection(editor.session) }

        func render(_ text: NSTextView, caret: Int? = nil) {
            guard !rendering else { return }
            let changed = renderedRevision != editor.session.revision
            let selectionChanged = selected != editor.selected
            guard changed || selectionChanged || caret != nil else { return }
            rendering = true
            defer { rendering = false }
            let oldRange = text.selectedRange()
            projection = PackageWritingProjection(editor.session)
            if changed {
                let content = NSMutableAttributedString(string: projection.text)
                let font = (NSFont(name: "Courier", size: 14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
                content.addAttributes([.font: font, .foregroundColor: NSColor.textColor], range: NSRange(location: 0, length: content.length))
                for entry in projection.entries {
                    let style = NSMutableParagraphStyle()
                    style.paragraphSpacing = 14
                    // Relative indents remain usable in a laptop-width writing pane.
                    switch entry.type {
                    case "character": style.firstLineHeadIndent = 190; style.headIndent = 190
                    case "dialogue": style.firstLineHeadIndent = 95; style.headIndent = 95; style.tailIndent = -70
                    case "parenthetical": style.firstLineHeadIndent = 135; style.headIndent = 135; style.tailIndent = -95
                    case "transition": style.alignment = .right
                    default: break
                    }
                    let length = entry.range.length + (NSMaxRange(entry.range) < content.length ? 1 : 0)
                    if length > 0 {
                        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: entry.range.location, length: length))
                        if entry.type == "scene_heading" {
                            content.addAttribute(.font, value: (NSFont(name: "Courier-Bold", size: 14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)), range: entry.range)
                        }
                    }
                }
                text.textStorage?.setAttributedString(content)
            }
            let location = caret ?? (selectionChanged ? projection.entries.first(where: { $0.id == editor.selected })?.range.location : nil) ?? oldRange.location
            let clamped = min(location, (projection.text as NSString).length)
            text.setSelectedRange(NSRange(location: clamped, length: caret == nil && !selectionChanged ? min(oldRange.length, (projection.text as NSString).length - clamped) : 0))
            text.typingAttributes = [.font: (NSFont(name: "Courier", size: 14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)), .foregroundColor: NSColor.textColor]
            if let entry = projection.position(clamped)?.0 {
                editor.selectWritingParagraph(entry.id)
            }
            selected = editor.selected; renderedRevision = editor.session.revision
            if caret != nil { text.scrollRangeToVisible(text.selectedRange()) }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !rendering, let text = notification.object as? NSTextView, !text.hasMarkedText(),
                  let entry = projection.position(text.selectedRange().location)?.0 else { return }
            selected = entry.id; editor.selectWritingParagraph(entry.id)
        }
        func replace(_ range: NSRange, with replacement: String, split: Bool, in text: NSTextView) -> Bool {
            guard let (first, start) = projection.position(range.location),
                  let (last, end) = projection.position(NSMaxRange(range)) else { return false }
            let prefix = String(first.text[..<start]), suffix = String(last.text[end...])
            let nextType = ["character", "parenthetical"].contains(first.type) ? "dialogue" : "action"
            guard editor.editWritingSpan(start: first.id, end: last.id, prefix: prefix,
                                         replacement: replacement, suffix: suffix, splitType: split ? nextType : nil) else { return false }
            if text.hasMarkedText() {
                // Keep provisional composition recoverable without resetting the native IME.
                projection = PackageWritingProjection(editor.session)
                renderedRevision = nil
            } else {
                render(text, caret: range.location + (replacement as NSString).length + (split ? 1 : 0))
            }
            return true
        }
        func textView(_ text: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !text.hasMarkedText() else { return false }
            if command == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) { return false }
                _ = replace(text.selectedRange(), with: "", split: true, in: text)
                return true
            }
            return false
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !rendering, let replacementString { nativeEdit = (affectedCharRange, replacementString) }
            return true
        }
        func textDidChange(_ notification: Notification) {
            guard !rendering, let text = notification.object as? NSTextView else { return }
            if let (range, replacement) = nativeEdit {
                nativeEdit = nil
                if let swiftRange = Range(range, in: projection.text) {
                    let expected = projection.text.replacingCharacters(in: swiftRange, with: replacement)
                    if expected.unicodeScalars.elementsEqual(text.string.unicodeScalars),
                       replace(range, with: replacement, split: false, in: text) { return }
                }
            }
            // Fallback for accessibility replacements that provide no native range.
            // Compare graphemes, retaining canonical Unicode spelling. This also handles
            // native Backspace across a boundary and selection replacements spanning rows.
            let before = Array(projection.text), after = Array(text.string)
            var prefix = 0
            while prefix < min(before.count, after.count), String(before[prefix]).unicodeScalars.elementsEqual(String(after[prefix]).unicodeScalars) { prefix += 1 }
            var suffix = 0
            while suffix < min(before.count, after.count) - prefix,
                  String(before[before.count - suffix - 1]).unicodeScalars.elementsEqual(String(after[after.count - suffix - 1]).unicodeScalars) { suffix += 1 }
            let start = (String(before[..<prefix]) as NSString).length
            let length = (String(before[prefix..<(before.count - suffix)]) as NSString).length
            let replacement = String(after[prefix..<(after.count - suffix)])
            if !replace(NSRange(location: start, length: length), with: replacement, split: false, in: text) {
                renderedRevision = nil; render(text)
            }
        }
    }
}
