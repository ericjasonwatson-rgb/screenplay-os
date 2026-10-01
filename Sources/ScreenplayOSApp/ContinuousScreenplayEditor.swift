import AppKit
import SwiftUI
import ScreenplayDomain

/// One native text view lets the system select, copy, and replace across element boundaries.
struct ContinuousScreenplayEditor: NSViewRepresentable {
    @ObservedObject var model: ScreenplayViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WritingScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        view.isRichText = false
        view.allowsUndo = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: 10000, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.delegate = context.coordinator
        scroll.documentView = view
        context.coordinator.render(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.model = model
        guard let view = scroll.documentView as? WritingTextView else { return }
        context.coordinator.render(view)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var model: ScreenplayViewModel
        var updating = false
        var pending: (NSRange, String, NSRange)?
        var restorationToken: UUID?
        var selectedID: UUID?
        init(_ model: ScreenplayViewModel) { self.model = model }

        fileprivate func render(_ view: WritingTextView) {
            guard !updating, !view.hasMarkedText() else { return }
            updating = true
            defer { updating = false }
            let scale = CGFloat(model.pageZoom)
            let oldSelection = view.selectedRange()
            let string = model.writingText
            let attributed = NSMutableAttributedString(string: string)
            let ranges = model.writingRanges
            var activeAttributes: [NSAttributedString.Key: Any] = [:]
            for (index, element) in model.elements.enumerated() {
                let style = ScreenplayBodyLayout.editorStyle(for: element.type, scale: scale)
                var range = ranges[index]
                if index < ranges.count - 1 { range.length += 1 }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: PackageTypography.font(model.writingTypography, displayScale: scale),
                    .foregroundColor: StudioAppearance.ink(model.darkPageMode),
                    .paragraphStyle: style
                ]
                if let mark = element.revisionMark {
                    attributes[.backgroundColor] = NSColor(mark.color.swiftUIColor).withAlphaComponent(0.15)
                }
                if range.length > 0 { attributed.addAttributes(attributes, range: range) }
                if element.runs != nil {
                    PackageTypography.apply(element.styledText, settings: model.writingTypography, to: attributed, offset: ranges[index].location, displayScale: scale)
                }
                if element.id == model.selectedElementID { activeAttributes = attributes }
            }
            view.displayScale = scale
            view.layoutPage(in: view.enclosingScrollView?.contentSize.width ?? 0)
            view.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.enclosingScrollView?.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.insertionPointColor = StudioAppearance.ink(model.darkPageMode)
            let changed = view.string != string
            if changed || view.textStorage?.isEqual(to: attributed) == false {
                view.textStorage?.setAttributedString(attributed)
            }
            let projection = model.printedLayout
            view.pageGuides = projection.unmappedElementIDs.isEmpty ? projection.pages.indices.compactMap { index in
                projection.firstSourceCaret(onPage: index).map { PrintedPageGuide(label: projection.pages[index].label, offset: $0.location) }
            } : []
            view.guideInk = StudioAppearance.ink(model.darkPageMode)
            view.needsDisplay = true
            var selection = oldSelection
            let restore = restorationToken != model.documentCaretToken
            let moved = selectedID != model.selectedElementID
            if restore, let caret = model.documentCaret {
                selection = caret
            } else if moved || (restore && model.documentCaret == nil) {
                if let index = model.elements.firstIndex(where: { $0.id == model.selectedElementID }) {
                    selection = NSRange(location: NSMaxRange(ranges[index]), length: 0)
                }
            } else if changed, let caret = model.documentCaret {
                selection = caret
            }
            let count = (string as NSString).length
            selection.location = min(selection.location, count)
            selection.length = min(selection.length, count - selection.location)
            view.setSelectedRange(selection)
            view.typingAttributes = activeAttributes
            restorationToken = model.documentCaretToken
            selectedID = model.selectedElementID
            view.formattingShortcut = { [weak self] key in
                self?.model.toggleWritingEmphasis(key == "b" ? \.bold : key == "i" ? \.italic : \.underline)
            }
            view.cycleType = { [weak self] forward in
                guard let self, let id = self.model.selectedElementID else { return }
                self.model.cycleElementType(for: id, forward: forward)
            }
            if moved || restore {
                view.scrollRangeToVisible(selection)
                if moved {
                    DispatchQueue.main.async { [weak view] in
                        guard let view, let window = view.window else { return }
                        window.makeFirstResponder(view)
                    }
                }
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !updating, let replacementString else { return !updating }
            pending = (affectedCharRange, replacementString, textView.selectedRange())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? WritingTextView, !view.hasMarkedText(),
                  let (range, replacement, selection) = pending else { return }
            pending = nil
            // Marked-text input may generate several native edits before committing.
            // Reconcile the committed string if the last delegate edit alone cannot describe it.
            var editRange = range
            var inserted = replacement
            var beforeSelection = selection
            let original = model.writingText as NSString
            if NSMaxRange(range) > original.length || original.replacingCharacters(in: range, with: replacement) != view.string {
                let old = Array(model.writingText)
                let new = Array(view.string)
                var prefix = 0
                while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
                var suffix = 0
                while suffix < min(old.count, new.count) - prefix,
                      old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
                editRange = NSRange(location: (String(old.prefix(prefix)) as NSString).length,
                    length: (String(old[prefix..<(old.count - suffix)]) as NSString).length)
                inserted = String(new[prefix..<(new.count - suffix)])
                beforeSelection = model.documentCaret ?? editRange
            }
            updating = true
            let caret = model.replaceWritingText(in: editRange, with: inserted,
                groupable: inserted.count <= 1 && !inserted.contains("\n"), selection: beforeSelection)
            updating = false
            // Normalize casing and structural edits immediately, before the next keystroke.
            selectedID = model.selectedElementID
            render(view)
            updating = true
            view.setSelectedRange(caret)
            view.scrollRangeToVisible(caret)
            updating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView,
                  view.string == model.writingText else { return }
            model.rememberDocumentCaret(view.selectedRange())
            selectedID = model.selectedElementID
        }
    }
}

private final class WritingScrollView: NSScrollView {
    override func tile() {
        super.tile()
        // SwiftUI may resize the page well after updateNSView has rendered.
        (documentView as? WritingTextView)?.layoutPage(in: contentSize.width)
    }
}

struct PrintedPageGuide: Equatable {
    let label: String
    let offset: Int
}

final class WritingTextView: NSTextView {
    var pageGuides: [PrintedPageGuide] = []
    var guideInk = NSColor.labelColor

    /// Uses the editable source glyph, never a fabricated newline or attachment.
    func pageGuidePoint(_ guide: PrintedPageGuide) -> NSPoint? {
        guard guide.offset >= 0, guide.offset < (string as NSString).length,
              let manager = layoutManager else { return nil }
        let range = NSRange(location: guide.offset, length: 1)
        manager.ensureLayout(forCharacterRange: range)
        let glyph = manager.glyphIndexForCharacter(at: guide.offset)
        let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = manager.location(forGlyphAt: glyph)
        return NSPoint(x: textContainerOrigin.x + rect.minX + location.x,
                       y: textContainerOrigin.y + rect.minY)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let manager = layoutManager, let container = textContainer else { return }
        // Only ask for glyph positions in the area being painted, avoiding full
        // document layout merely to draw guides far below the viewport.
        let local = rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: local, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let font = NSFont.systemFont(ofSize: 9 * displayScale)
        for guide in pageGuides where NSLocationInRange(guide.offset, characters) {
            guard let point = pageGuidePoint(guide) else { continue }
            let label = "PDF \(guide.label)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: guideInk.withAlphaComponent(0.55)]
            let width = label.size(withAttributes: attributes).width
            label.draw(at: NSPoint(x: max(4, textContainerOrigin.x - width - 12 * displayScale), y: point.y), withAttributes: attributes)
            // A short tick marks the exact source start when the PDF break falls
            // within a continuous editor line. It is paint only, not editable text.
            guideInk.withAlphaComponent(0.35).setStroke()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: point.x, y: point.y))
            tick.line(to: NSPoint(x: point.x, y: point.y + 3 * displayScale))
            tick.lineWidth = 0.5
            tick.stroke()
        }
    }

    var displayScale: CGFloat = 1
    private var layingOutPage = false

    func layoutPage(in availableWidth: CGFloat) {
        guard !layingOutPage else { return }
        layingOutPage = true
        defer { layingOutPage = false }
        let width = max(576 * displayScale, availableWidth)
        let minimum = NSSize(width: width, height: 792 * displayScale)
        let inset = NSSize(width: (width - ScreenplayBodyLayout.textWidth * displayScale) / 2, height: 48 * displayScale)
        // Lower the previous minimum before shrinking after zoom-out.
        if minSize != minimum { minSize = minimum }
        if textContainerInset != inset { textContainerInset = inset }
        let containerSize = NSSize(width: ScreenplayBodyLayout.textWidth * displayScale, height: CGFloat.greatestFiniteMagnitude)
        if textContainer?.containerSize != containerSize { textContainer?.containerSize = containerSize }
        let size = NSSize(width: width, height: max(frame.height, minimum.height))
        if frame.size != size { setFrameSize(size) }
    }

    var cycleType: ((Bool) -> Void)?
    var formattingShortcut: ((String) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased(), ["b", "i", "u"].contains(key) {
            formattingShortcut?(key); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
    override func insertTab(_ sender: Any?) { cycleType?(true) }
    override func insertBacktab(_ sender: Any?) { cycleType?(false) }
}
