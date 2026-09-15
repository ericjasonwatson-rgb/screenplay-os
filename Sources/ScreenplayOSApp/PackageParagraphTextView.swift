import AppKit
import SwiftUI
import ScreenplayDomain

/// Maps the continuous native text surface back to stable paragraph identities.
struct PackageWritingProjection {
    struct Entry { let id: UUID; let type: String; let range: NSRange; let text: String }
    var entries: [Entry]
    var text: String
    init(_ session: PackageTextSession) {
        var entries: [Entry] = [], text = "", offset = 0
        for row in session.paragraphs {
            if !entries.isEmpty { text += "\n"; offset += 1 }
            let value = (try? session.text(for: row.id)) ?? ""
            entries.append(Entry(id: row.id, type: row.type,
                                 range: NSRange(location: offset, length: (value as NSString).length), text: value))
            text += value; offset += (value as NSString).length
        }
        self.entries = entries; self.text = text
    }
    mutating func updateParagraph(_ id: UUID, value: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[index]
        text = (text as NSString).replacingCharacters(in: old.range, with: value)
        let length = (value as NSString).length, delta = length - old.range.length
        entries[index] = Entry(id: id, type: old.type, range: NSRange(location: old.range.location, length: length), text: value)
        for i in (index + 1)..<entries.count {
            let entry = entries[i]
            entries[i] = Entry(id: entry.id, type: entry.type, range: NSRange(location: entry.range.location + delta, length: entry.range.length), text: entry.text)
        }
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

/// Clipboard commands and focus changes end a typing group even for one character.
final class PackageWritingNativeTextView: NSTextView, NSLayoutManagerDelegate {
    static let pageGap: CGFloat = 24
    var darkPage = false
    var pagePlan: PackagePrintLayout.Plan?
    private var pageRevision: UUID?
    private var plannedLines: [Int: NSRect] = [:]
    private var plannedExtra: NSRect = .zero
    var pageCount: Int { max(1, pagePlan?.ranges.count ?? 1) }
    var pageStride: CGFloat { PackagePageGeometry.height + Self.pageGap }
    var pageHeight: CGFloat { CGFloat(pageCount) * pageStride - Self.pageGap }
    func paginate(_ session: PackageTextSession) throws {
        guard pageRevision != session.revision else { return }
        let plan = try PackagePrintLayout.plan(session, reusing: pagePlan)
        var lines: [Int: NSRect] = [:]
        for (page, range) in plan.glyphRanges.enumerated() {
            plan.layout.enumerateLineFragments(forGlyphRange: range) { rect, _, _, glyphs, _ in
                let start = plan.layout.characterIndexForGlyph(at: glyphs.location)
                var target = rect
                target.origin.y += CGFloat(page) * self.pageStride + plan.headerHeights[page]
                lines[start] = target
            }
        }
        pagePlan = plan; plannedLines = lines; pageRevision = session.revision
        plannedExtra = plan.layout.extraLineFragmentRect
        plannedExtra.origin.y += CGFloat(pageCount - 1) * pageStride + (plan.headerHeights.last ?? 0)
        layoutManager?.delegate = self
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: plan.relayoutStart, length: (string as NSString).length - plan.relayoutStart), actualCharacterRange: nil)
        if let container = textContainer, let manager = layoutManager {
            manager.ensureLayout(for: container)
            if string.isEmpty || string.hasSuffix("\n") {
                var used = plannedExtra; used.size.width = 0
                manager.setExtraLineFragmentRect(plannedExtra, usedRect: used, textContainer: container)
            }
        }
        setFrameSize(NSSize(width: PackagePageGeometry.width, height: pageHeight))
        needsDisplay = true
    }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        let character = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        guard let target = plannedLines[character] else { return false }
        lineFragmentRect.pointee.origin.y = target.origin.y
        lineFragmentUsedRect.pointee.origin.y = target.origin.y
        return true
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let ink = StudioAppearance.ink(darkPage)
        let font = pagePlan?.font ?? StudioAppearance.courier(size: 12)
        for page in 0..<pageCount {
            guard NSRect(x: 0, y: CGFloat(page) * pageStride - Self.pageGap, width: bounds.width, height: pageStride).intersects(rect) else { continue }
            let offset = CGFloat(page) * pageStride
            if page > 0 {
                NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
                NSRect(x: 0, y: offset - Self.pageGap, width: bounds.width, height: Self.pageGap).fill()
            }
            ("\(page + 1)." as NSString).draw(at: NSPoint(x: 516, y: offset + 36), withAttributes: [.font: font, .foregroundColor: ink])
            if let plan = pagePlan {
                if let header = plan.headers[page] {
                    (header as NSString).draw(with: NSRect(x: 252, y: offset + 72, width: 288, height: plan.headerHeights[page]),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .foregroundColor: ink])
                }
                if plan.footers[page] {
                    ("(MORE)" as NSString).draw(at: NSPoint(x: 252, y: offset + 700), withAttributes: [.font: font, .foregroundColor: ink])
                }
            }
        }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: PackagePageGeometry.width, height: max(pageHeight, newSize.height)))
    }
    override var textContainerOrigin: NSPoint {
        NSPoint(x: PackagePageGeometry.left, y: PackagePageGeometry.top)
    }
    var historyBoundary: (() -> Void)?
    var formattingShortcut: ((String) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if window?.firstResponder === self, flags == .command, let key = event.charactersIgnoringModifiers?.lowercased(), ["b", "i", "u"].contains(key), let formattingShortcut {
            formattingShortcut(key); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) {
        historyBoundary?(); super.paste(sender); historyBoundary?()
    }
    override func cut(_ sender: Any?) {
        historyBoundary?(); super.cut(sender); historyBoundary?()
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { historyBoundary?() }
        return result
    }
}

/// One native text view provides continuous selection, navigation, and copying.
struct PackageParagraphTextView: NSViewRepresentable {
    @ObservedObject var editor: PackageEditor
    func makeCoordinator() -> Coordinator { Coordinator(editor) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PackageWritingNativeTextView.scrollableTextView()
        let text = scroll.documentView as! PackageWritingNativeTextView
        text.historyBoundary = { [weak editor] in editor?.typingBoundary = UUID() }
        text.formattingShortcut = { [weak editor] key in
            guard let editor else { return }
            editor.toggleEmphasis(key == "b" ? \.bold : key == "i" ? \.italic : \.underline)
        }
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.allowsUndo = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = []
        text.minSize = NSSize(width: PackagePageGeometry.width, height: PackagePageGeometry.height)
        text.maxSize = NSSize(width: PackagePageGeometry.width, height: CGFloat.greatestFiniteMagnitude)
        text.setFrameSize(text.minSize)
        text.textContainerInset = NSSize(width: (PackagePageGeometry.left + PackagePageGeometry.right) / 2, height: PackagePageGeometry.top)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: PackagePageGeometry.textWidth, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
        text.setAccessibilityLabel("Screenplay text")
        text.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        context.coordinator.editor = editor
        guard !text.hasMarkedText() else {
            editor.updateCharacterSuggestions(atEnd: false)
            return
        }
        context.coordinator.render(text)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: PackageEditor
        var projection: PackageWritingProjection
        var rendering = false
        var renderedDarkPage: Bool?
        var renderedRevision: UUID?
        var selected: UUID?
        var nativeEdit: (NSRange, String)?
        var nativeSelection: NSRange?
        var typingGroup: (id: UUID, element: UUID, caret: Int, backward: Bool, time: TimeInterval, revision: UUID, boundary: UUID)?
        init(_ editor: PackageEditor) { self.editor = editor; projection = PackageWritingProjection(editor.session) }

        static func attributes(for type: String, dark: Bool = false, settings: DocumentTypography? = nil) -> [NSAttributedString.Key: Any] {
            let style = PackagePageGeometry.paragraphStyle(for: type)
            let font = PackageTypography.font(settings ?? (try! DocumentTypography()), displayScale: 1)
            return [.font: font, .foregroundColor: StudioAppearance.ink(dark), .paragraphStyle: style]
        }
        func render(_ text: NSTextView, caret: Int? = nil) {
            guard !rendering else { return }
            let changed = renderedRevision != editor.session.revision || renderedDarkPage != editor.darkPageMode
            let dark = editor.darkPageMode
            (text as? PackageWritingNativeTextView)?.darkPage = dark
            text.backgroundColor = StudioAppearance.paper(dark)
            text.enclosingScrollView?.backgroundColor = StudioAppearance.paper(dark)
            text.insertionPointColor = StudioAppearance.ink(dark)
            let selectionChanged = selected != editor.selected
            guard changed || selectionChanged || caret != nil || editor.requestedFindSelection != nil else { return }
            rendering = true
            defer { rendering = false }
            let oldRange = text.selectedRange()
            if changed {
                projection = PackageWritingProjection(editor.session)
                let content = NSMutableAttributedString(string: projection.text)
                let font = (NSFont(name: "Courier", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
                content.addAttributes([.font: font, .foregroundColor: StudioAppearance.ink(dark)], range: NSRange(location: 0, length: content.length))
                for entry in projection.entries {
                    let attributes = Self.attributes(for: entry.type, dark: editor.darkPageMode, settings: editor.session.typography)
                    let length = entry.range.length + (NSMaxRange(entry.range) < content.length ? 1 : 0)
                    if length > 0 {
                        content.addAttributes(attributes, range: NSRange(location: entry.range.location, length: length))
                    }
                }
                for entry in projection.entries {
                    if let styled = try? editor.session.styledText(for: entry.id) {
                        PackageTypography.apply(styled, settings: editor.session.typography, to: content, offset: entry.range.location, displayScale: 1)
                    }
                }
                text.textStorage?.setAttributedString(content)
            }
            if let native = text as? PackageWritingNativeTextView {
                do { try native.paginate(editor.session) }
                catch { editor.message = "Page layout could not be updated. Your text is retained." }
            }
            let findSelection = editor.requestedFindSelection
            editor.requestedFindSelection = nil
            let restored = findSelection ?? editor.restoredWritingSelection
            editor.restoredWritingSelection = nil
            let completionCaret = editor.completionCaret
            editor.completionCaret = nil
            let location = restored?.location ?? completionCaret ?? caret ?? (selectionChanged ? projection.entries.first(where: { $0.id == editor.selected })?.range.location : nil) ?? oldRange.location
            let clamped = min(location, (projection.text as NSString).length)
            text.setSelectedRange(NSRange(location: clamped, length: min(restored?.length ?? (caret == nil && completionCaret == nil && !selectionChanged ? oldRange.length : 0), (projection.text as NSString).length - clamped)))
            text.typingAttributes = Self.attributes(for: projection.position(clamped)?.0.type ?? "action", dark: dark, settings: editor.session.typography)
            if let entry = projection.position(clamped)?.0 {
                editor.selectWritingParagraph(entry.id)
            }
            selected = editor.selected; renderedRevision = editor.session.revision; renderedDarkPage = dark
            if caret != nil || completionCaret != nil || restored != nil { text.scrollRangeToVisible(text.selectedRange()) }
            if completionCaret != nil || (findSelection != nil && !editor.findVisible) { text.window?.makeFirstResponder(text) }
            editor.didRenderWritingSelection(text.selectedRange())
            updateSuggestions(text)
        }
        func updateSuggestions(_ text: NSTextView) {
            let range = text.selectedRange()
            let entry = projection.position(range.location)?.0
            editor.updateCharacterSuggestions(atEnd: !text.hasMarkedText() && range.length == 0 && entry.map { NSMaxRange($0.range) == range.location } == true)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !rendering, let text = notification.object as? NSTextView, !text.hasMarkedText(),
                  let entry = projection.position(text.selectedRange().location)?.0 else { return }
            if nativeEdit == nil { typingGroup = nil; editor.moveWritingSelection(text.selectedRange()) }
            selected = entry.id; editor.selectWritingParagraph(entry.id)
            text.typingAttributes = Self.attributes(for: entry.type, dark: editor.darkPageMode, settings: editor.session.typography)
            updateSuggestions(text)
        }
        func replace(_ range: NSRange, with replacement: String, split: Bool, in text: NSTextView) -> Bool {
            guard let (first, start) = projection.position(range.location),
                  let (last, end) = projection.position(NSMaxRange(range)) else { return false }
            let prefix = String(first.text[..<start]), suffix = String(last.text[end...])
            let nextType = ["character", "parenthetical"].contains(first.type) ? "dialogue" : "action"
            let beforeSelection = nativeSelection ?? text.selectedRange()
            nativeSelection = nil
            editor.writingSelection = beforeSelection
            let now = ProcessInfo.processInfo.systemUptime
            let deleted = Range(range, in: projection.text).map { String(projection.text[$0]) } ?? ""
            let insertion = range.length == 0 && replacement.count == 1 && !replacement.contains("\n")
            let backward = replacement.isEmpty && deleted.count == 1 && NSMaxRange(range) == beforeSelection.location
            let groupingAllowed = !split && first.id == last.id && beforeSelection.length == 0 && !text.hasMarkedText()
                && !(NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) && (insertion || backward)
            let continueGroup = groupingAllowed && typingGroup.map {
                $0.element == first.id && $0.caret == beforeSelection.location && $0.backward == backward
                    && now - $0.time < 1 && $0.revision == editor.session.revision && $0.boundary == editor.typingBoundary
            } == true
            let groupID: UUID? = groupingAllowed ? (continueGroup ? typingGroup!.id : UUID()) : nil
            guard editor.editWritingSpan(start: first.id, end: last.id, prefix: prefix,
                                         replacement: replacement, suffix: suffix, splitType: split ? nextType : nil, historyGroup: groupID) else { return false }
            typingGroup = groupID.map { ($0, first.id, range.location + (replacement as NSString).length, backward, now, editor.session.revision, editor.typingBoundary) }
            if first.id == last.id && !split {
                projection.updateParagraph(first.id, value: prefix + replacement + suffix)
                // Native input already changed the characters. Restyle only this paragraph.
                if !text.hasMarkedText(), text.string.unicodeScalars.elementsEqual(projection.text.unicodeScalars),
                   let updated = projection.entries.first(where: { $0.id == first.id }) {
                    rendering = true
                    let length = updated.range.length + (NSMaxRange(updated.range) < (projection.text as NSString).length ? 1 : 0)
                    text.textStorage?.addAttributes(Self.attributes(for: updated.type, dark: editor.darkPageMode, settings: editor.session.typography), range: NSRange(location: updated.range.location, length: length))
                    if let storage = text.textStorage, let styled = try? editor.session.styledText(for: updated.id) {
                        storage.removeAttribute(.underlineStyle, range: NSRange(location: updated.range.location, length: length))
                        storage.removeAttribute(.strikethroughStyle, range: NSRange(location: updated.range.location, length: length))
                        PackageTypography.apply(styled, settings: editor.session.typography, to: storage, offset: updated.range.location, displayScale: 1)
                    }
                    rendering = false
                    renderedRevision = editor.session.revision
                    selected = editor.selected
                }
            }
            if text.hasMarkedText() {
                editor.updateCharacterSuggestions(atEnd: false)
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
            if command == #selector(NSResponder.insertTab(_:)) || command == #selector(NSResponder.insertBacktab(_:)) {
                let range = text.selectedRange()
                guard let entry = projection.position(range.location)?.0,
                      NSMaxRange(range) <= NSMaxRange(entry.range),
                      let index = PackageTextSession.supportedTypes.firstIndex(of: entry.type) else { return true }
                let types = PackageTextSession.supportedTypes
                let delta = command == #selector(NSResponder.insertTab(_:)) ? 1 : -1
                editor.selectWritingParagraph(entry.id)
                editor.changeType(types[(index + delta + types.count) % types.count])
                editor.dismissCharacterSuggestions()
                render(text)
                return true
            }
            if command == #selector(NSResponder.cancelOperation(_:)), !editor.characterSuggestions.isEmpty {
                editor.dismissCharacterSuggestions(); return true
            }
            if command == #selector(NSResponder.cancelOperation(_:)), editor.findVisible {
                editor.closeFind(); return true
            }
            if command == #selector(NSResponder.moveDown(_:)), !editor.characterSuggestions.isEmpty {
                editor.highlightedSuggestion = ((editor.highlightedSuggestion ?? -1) + 1) % editor.characterSuggestions.count
                return true
            }
            if command == #selector(NSResponder.moveUp(_:)), let index = editor.highlightedSuggestion {
                editor.highlightedSuggestion = index == 0 ? nil : index - 1
                return true
            }
            if command == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) { return false }
                if let index = editor.highlightedSuggestion, editor.characterSuggestions.indices.contains(index) {
                    _ = editor.acceptCharacterSuggestion(editor.characterSuggestions[index])
                    render(text)
                    return true
                }
                _ = replace(text.selectedRange(), with: "", split: true, in: text)
                return true
            }
            return false
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !rendering, let replacementString { nativeSelection = textView.selectedRange(); nativeEdit = (affectedCharRange, replacementString) }
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
