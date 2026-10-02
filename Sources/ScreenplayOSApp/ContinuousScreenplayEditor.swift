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
        scroll.minMagnification = 0.5; scroll.maxMagnification = 3
        scroll.allowsMagnification = false
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
        var writingProjection = ScreenplayWritingProjection(elements: [])
        var pageCache: (elements: [ScreenplayElement], lock: ProductionPageLock?, typography: DocumentTypography, plan: PrintedWritingLayout?)?
        init(_ model: ScreenplayViewModel) { self.model = model }

        fileprivate func render(_ view: WritingTextView) {
            guard !updating, !view.hasMarkedText() else { return }
            updating = true
            defer { updating = false }
            let scale: CGFloat = 1
            (view.enclosingScrollView as? WritingScrollView)?.pageZoom = CGFloat(model.pageZoom)
            let oldSelection = writingProjection.sourceRange(view.selectedRange())
            writingProjection = ScreenplayWritingProjection(elements: model.elements)
            let string = writingProjection.text
            let attributed = NSMutableAttributedString(string: string)
            let ranges = writingProjection.ranges
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
                    PackageTypography.apply((try? element.styledText.replacingText(model.displayedText(for: element))) ?? element.styledText, settings: model.writingTypography, to: attributed, offset: ranges[index].location, displayScale: scale)
                }
                if element.id == model.selectedElementID { activeAttributes = attributes }
            }
            view.displayScale = scale
            view.layoutPage(in: (view.enclosingScrollView?.contentSize.width ?? 0) / CGFloat(model.pageZoom))
            view.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.enclosingScrollView?.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.insertionPointColor = StudioAppearance.ink(model.darkPageMode)
            let changed = view.string != string
            if changed || view.textStorage?.isEqual(to: attributed) == false {
                view.textStorage?.setAttributedString(attributed)
            }
            let projection = model.printedLayout
            view.pageGuides = projection.unmappedElementIDs.isEmpty ? projection.pages.indices.compactMap { index in
                projection.firstSourceCaret(onPage: index).map { PrintedPageGuide(label: projection.pages[index].label, offset: writingProjection.displayRange($0).location) }
            } : []
            view.guideInk = StudioAppearance.ink(model.darkPageMode)
            if pageCache?.elements != model.elements || pageCache?.lock != model.document?.screenplay.pageLock || pageCache?.typography != model.writingTypography {
                pageCache = (model.elements, model.document?.screenplay.pageLock, model.writingTypography,
                    PrintedWritingLayout(print: projection, writing: writingProjection, typography: model.writingTypography))
            }
            view.setPagePlan(pageCache?.plan)
            let available = view.pagePlan != nil
            if model.writingPageLayoutAvailable != available {
                DispatchQueue.main.async { [weak self] in self?.model.writingPageLayoutAvailable = available }
            }
            view.needsDisplay = true
            var selection = oldSelection
            let restore = restorationToken != model.documentCaretToken
            let moved = selectedID != model.selectedElementID
            if restore, let caret = model.documentCaret {
                selection = caret
            } else if moved || (restore && model.documentCaret == nil) {
                if let index = model.elements.firstIndex(where: { $0.id == model.selectedElementID }) {
                    selection = NSRange(location: NSMaxRange(model.writingRanges[index]), length: 0)
                }
            } else if changed, let caret = model.documentCaret {
                selection = caret
            }
            selection = writingProjection.displayRange(selection)
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
            let original = writingProjection.text as NSString
            if NSMaxRange(range) > original.length || original.replacingCharacters(in: range, with: replacement) != view.string {
                let old = Array(writingProjection.text)
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
            let caret = model.replaceWritingText(in: writingProjection.sourceRange(editRange), with: inserted,
                groupable: inserted.count <= 1 && !inserted.contains("\n"), selection: writingProjection.sourceRange(beforeSelection))
            updating = false
            // Normalize casing and structural edits immediately, before the next keystroke.
            selectedID = model.selectedElementID
            render(view)
            updating = true
            let displayedCaret = writingProjection.displayRange(caret)
            view.setSelectedRange(displayedCaret)
            view.scrollRangeToVisible(displayedCaret)
            updating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView,
                  view.string == writingProjection.text else { return }
            model.rememberDocumentCaret(writingProjection.sourceRange(view.selectedRange()))
            selectedID = model.selectedElementID
        }
    }
}

private final class WritingScrollView: NSScrollView {
    var pageZoom: CGFloat = 1 { didSet { applyZoom() } }
    private var applyingZoom = false
    override func tile() {
        super.tile()
        applyZoom()
        (documentView as? WritingTextView)?.layoutPage(in: contentSize.width / pageZoom)
    }
    private func applyZoom() {
        guard !applyingZoom, documentView != nil else { return }
        applyingZoom = true
        defer { applyingZoom = false }
        if abs(magnification - pageZoom) > 0.0001 {
            let visible = documentVisibleRect
            setMagnification(pageZoom, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        }
    }
}

struct PrintedPageGuide: Equatable {
    let label: String
    let offset: Int
}

final class WritingTextView: NSTextView, NSLayoutManagerDelegate {
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

    private(set) var pagePlan: PrintedWritingLayout?
    private var attemptedPlanID: UUID?
    func setPagePlan(_ plan: PrintedWritingLayout?) {
        if let id = plan?.id, attemptedPlanID == id { return }
        attemptedPlanID = plan?.id
        // Validate natural wrapping before applying page coordinates. A mismatched
        // line can otherwise make TextKit repeatedly backtrack during layout.
        pagePlan = nil
        layoutManager?.delegate = self
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
        if let manager = layoutManager, let container = textContainer {
            manager.ensureLayout(for: container)
            if string.isEmpty || string.hasSuffix("\n"), let line = plan?.lines[(string as NSString).length] {
                let rect = NSRect(x: 0, y: line.y * displayScale, width: container.containerSize.width, height: line.height * displayScale)
                manager.setExtraLineFragmentRect(rect, usedRect: rect, textContainer: container)
            }
        }
        if let plan, let manager = layoutManager, let container = textContainer {
            var starts = Set<Int>()
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, range, _ in
                starts.insert(manager.characterIndexForGlyph(at: range.location))
            }
            if string.isEmpty || string.hasSuffix("\n") { starts.insert((string as NSString).length) }
            guard Set(plan.lines.keys).isSubset(of: starts) else {
                // Never draw a mixture of paged and continuous coordinates.
                pagePlan = nil
                manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
                manager.ensureLayout(for: container)
                return
            }
            pagePlan = plan
            manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
            manager.ensureLayout(for: container)
            setFrameSize(NSSize(width: frame.width, height: (CGFloat(plan.labels.count) * PrintedWritingLayout.stride - 24) * displayScale))
        }
    }
    func layoutManager(_ manager: NSLayoutManager, shouldSetLineFragmentRect rect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect used: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
        in container: NSTextContainer, forGlyphRange glyphs: NSRange) -> Bool {
        let start = manager.characterIndexForGlyph(at: glyphs.location)
        guard let line = pagePlan?.lines[start] else { return false }
        rect.pointee.origin.y = line.y * displayScale
        used.pointee.origin.y = line.y * displayScale
        rect.pointee.size.height = line.height * displayScale
        used.pointee.size.height = line.height * displayScale
        baselineOffset.pointee = line.baseline * displayScale
        return true
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let plan = pagePlan else { return }
        for (index, label) in plan.labels.enumerated() {
            let top = CGFloat(index) * PrintedWritingLayout.stride * displayScale
            if index > 0 {
                NSColor(calibratedWhite: 0.24, alpha: 1).setFill()
                NSRect(x: 0, y: top - 24 * displayScale, width: bounds.width, height: 24 * displayScale).fill()
            }
            (label + "." as String).draw(at: NSPoint(x: textContainerOrigin.x + 432 * displayScale, y: top + 36 * displayScale),
                withAttributes: [.font: StudioAppearance.courier(size: 12 * displayScale), .foregroundColor: guideInk])
        }
        for mark in plan.marks {
            var attrs = mark.attributes
            if let font = attrs[.font] as? NSFont { attrs[.font] = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * displayScale) }
            attrs[.foregroundColor] = guideInk
            let area = NSRect(x: textContainerOrigin.x + (mark.rect.minX - 108) * displayScale, y: mark.rect.minY * displayScale,
                width: mark.rect.width * displayScale, height: mark.rect.height * displayScale)
            if area.intersects(rect) { mark.text.draw(in: area, withAttributes: attrs) }
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
        let inset = NSSize(width: (width - ScreenplayBodyLayout.textWidth * displayScale) / 2, height: 72 * displayScale)
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
