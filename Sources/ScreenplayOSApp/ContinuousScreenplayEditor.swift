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
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
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
        // Script-editing menu commands (Delete, Tab, ⌘1–⌘7) follow the editor's focus.
        let focusModel = model
        view.focusChanged = { [weak focusModel] focused in
            DispatchQueue.main.async { focusModel?.setScriptEditorFocused(focused) }
        }
        scroll.documentView = view
        scroll.viewportChanged = { [weak coordinator = context.coordinator] in
            coordinator?.updateVisiblePage()
        }
        context.coordinator.scrollView = scroll
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
        weak var scrollView: NSScrollView?
        var pagePositions: [(label: String, y: CGFloat)] = []
        var pendingViewportUpdate = false

        func updateVisiblePage() {
            guard !pendingViewportUpdate else { return }
            pendingViewportUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingViewportUpdate = false
                guard let scroll = self.scrollView else { return }
                // Read document coordinates so zoom never changes the page identity.
                let top = scroll.documentVisibleRect.minY
                let label = self.pagePositions.last(where: { $0.y <= top + 1 })?.label ?? self.pagePositions.first?.label
                if self.model.scriptViewport.pageLabel != label {
                    self.model.scriptViewport.pageLabel = label
                }
            }
        }

        var updating = false
        var pending: (NSRange, String, NSRange)?
        var restorationToken: UUID?
        var selectedID: UUID?
        var writingProjection = ScreenplayWritingProjection(elements: [])
        private var projectedElements: [ScreenplayElement]?
        let measurements = PrintedWritingLayout.MeasurementCache()
        let textRenderCache = WritingTextRenderCache()
        // Opt-in timing only; never records screenplay content or identifiers.
        private let traceTyping = ProcessInfo.processInfo.environment["SCREENPLAYOS_TRACE_TYPING"] == "1"
        private var renderPhases: [Double] = []
        var nativeEditRange: NSRange?
        var pageCache: (elements: [ScreenplayElement], lock: ProductionPageLock?, typography: DocumentTypography, lineLayout: ScreenplayLineLayout, plan: PrintedWritingLayout?)?
        init(_ model: ScreenplayViewModel) { self.model = model }

        fileprivate func render(_ view: WritingTextView) {
            guard !updating, !view.hasMarkedText() else { return }
            updating = true
            defer { updating = false }
            var phaseStart = traceTyping ? ProcessInfo.processInfo.systemUptime : 0
            var phases: [Double] = []
            func checkpoint() {
                guard traceTyping else { return }
                let now = ProcessInfo.processInfo.systemUptime
                phases.append((now - phaseStart) * 1000)
                phaseStart = now
            }
            defer { if traceTyping { renderPhases = phases } }
            let scale: CGFloat = 1
            (view.enclosingScrollView as? WritingScrollView)?.pageZoom = CGFloat(model.pageZoom)
            let oldSelection = writingProjection.sourceRange(view.selectedRange())
            if projectedElements != model.elements {
                writingProjection = ScreenplayWritingProjection(elements: model.elements, casing: model.screenplayCasing)
                projectedElements = model.elements
            }
            let string = writingProjection.text
            let changed = view.string != string
            checkpoint() // Writing projection and native string comparison.
            let activeAttributes: [NSAttributedString.Key: Any]
            if let storage = view.textStorage {
                activeAttributes = textRenderCache.update(storage, elements: model.elements,
                    projection: writingProjection, typography: model.writingTypography,
                    dark: model.darkPageMode, selectedID: model.selectedElementID, nativeEdit: nativeEditRange, lineLayout: model.effectiveLineLayout)
            } else { activeAttributes = [:] }
            checkpoint() // Attributed paragraph update.
            nativeEditRange = nil
            view.displayScale = scale
            view.layoutPage(in: (view.enclosingScrollView?.contentSize.width ?? 0) / CGFloat(model.pageZoom))
            view.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.enclosingScrollView?.backgroundColor = StudioAppearance.paper(model.darkPageMode)
            view.enclosingScrollView?.verticalScroller?.knobStyle = model.darkPageMode ? .light : .dark
            view.enclosingScrollView?.horizontalScroller?.knobStyle = model.darkPageMode ? .light : .dark
            view.insertionPointColor = StudioAppearance.ink(model.darkPageMode)
            let projection = model.printedLayout
            checkpoint() // Page geometry and print projection.
            view.pageGuides = projection.unmappedElementIDs.isEmpty ? projection.pages.indices.compactMap { index in
                projection.firstSourceCaret(onPage: index).map { PrintedPageGuide(label: projection.pages[index].label, offset: writingProjection.displayRange($0).location) }
            } : []
            view.guideInk = StudioAppearance.ink(model.darkPageMode)
            if pageCache?.elements != model.elements || pageCache?.lock != model.document?.screenplay.pageLock || pageCache?.typography != model.writingTypography || pageCache?.lineLayout != model.effectiveLineLayout {
                pageCache = (model.elements, model.document?.screenplay.pageLock, model.writingTypography, model.effectiveLineLayout,
                    PrintedWritingLayout(print: projection, writing: writingProjection, typography: model.writingTypography, cache: measurements, lineLayout: model.effectiveLineLayout))
            }
            checkpoint() // Page guides and measured layout plan.
            view.setPagePlan(pageCache?.plan, invalidatedFrom: textRenderCache.lastReplacementRange?.location, updatedRange: textRenderCache.lastUpdatedRange)
            if let plan = view.pagePlan {
                pagePositions = plan.labels.enumerated().map { ($0.element, CGFloat($0.offset) * PrintedWritingLayout.stride * view.displayScale) }
            } else {
                pagePositions = view.pageGuides.compactMap { guide in
                    view.pageGuidePoint(guide).map { (guide.label, $0.y) }
                }
            }
            checkpoint() // Native page-plan installation and page positions.
            updateVisiblePage()
            let available = view.pagePlan != nil
            if model.writingPageLayoutAvailable != available {
                DispatchQueue.main.async { [weak self] in self?.model.writingPageLayoutAvailable = available }
            }
            view.setNeedsDisplay(view.visibleRect)
            var selection = oldSelection
            let restore = restorationToken != model.documentCaretToken
            let moved = selectedID != model.selectedElementID
            // A stored caret is only restored while it still belongs to the selected
            // element. Navigation from Outline, Shot, Boards, or Edit changes the
            // selection without moving the caret, and must not reopen an old scene.
            let selectedRange = model.elements.firstIndex(where: { $0.id == model.selectedElementID })
                .flatMap { model.writingRanges.indices.contains($0) ? model.writingRanges[$0] : nil }
            let caretMatchesSelection = { (caret: NSRange) -> Bool in
                guard let range = selectedRange else { return true }
                return caret.location >= range.location && caret.location <= NSMaxRange(range)
            }
            if restore, let caret = model.documentCaret, caretMatchesSelection(caret) {
                selection = caret
            } else if moved || restore {
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
                if let label = model.requestedPrintedPageLabel,
                   let page = pagePositions.first(where: { $0.label == label }),
                   let scroll = view.enclosingScrollView {
                    scroll.contentView.scroll(to: NSPoint(x: scroll.documentVisibleRect.minX, y: page.y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                model.requestedPrintedPageLabel = nil
                if moved || restore {
                    DispatchQueue.main.async { [weak view] in
                        guard let view, let window = view.window else { return }
                        window.makeFirstResponder(view)
                    }
                }
            }
            checkpoint() // Selection, scroll and display invalidation.
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !updating, let replacementString else { return !updating }
            pending = (affectedCharRange, replacementString, textView.selectedRange())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? WritingTextView, !view.hasMarkedText(),
                  let (range, replacement, selection) = pending else { return }
            let startedAt = traceTyping ? ProcessInfo.processInfo.systemUptime : 0
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
            let reconciledAt = traceTyping ? ProcessInfo.processInfo.systemUptime : 0
            updating = true
            let caret = model.replaceWritingText(in: writingProjection.sourceRange(editRange), with: inserted,
                groupable: inserted.count <= 1 && !inserted.contains("\n"), selection: writingProjection.sourceRange(beforeSelection))
            let mutatedAt = traceTyping ? ProcessInfo.processInfo.systemUptime : 0
            updating = false
            // Normalize casing and structural edits immediately, before the next keystroke.
            selectedID = model.selectedElementID
            nativeEditRange = editRange
            render(view)
            let renderedAt = traceTyping ? ProcessInfo.processInfo.systemUptime : 0
            updating = true
            let displayedCaret = writingProjection.displayRange(caret)
            view.setSelectedRange(displayedCaret)
            view.scrollRangeToVisible(displayedCaret)
            updating = false
            model.chromeState.refresh(from: model)
            if traceTyping {
                let endedAt = ProcessInfo.processInfo.systemUptime
                print("SCREENPLAYOS_INPUT_PHASES_MS=\([reconciledAt - startedAt, mutatedAt - reconciledAt, renderedAt - mutatedAt, endedAt - renderedAt].map { $0 * 1000 })")
                print("SCREENPLAYOS_RENDER_PHASES_MS=\(renderPhases)")
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, restorationToken == model.documentCaretToken,
                  let view = notification.object as? NSTextView,
                  view.string == writingProjection.text else { return }
            model.rememberDocumentCaret(writingProjection.sourceRange(view.selectedRange()))
            selectedID = model.selectedElementID
            // Publish completed selection state before the host layout, as for typing.
            // Otherwise queued chrome changes can trigger another full layout pass.
            model.chromeState.refresh(from: model)
        }
    }
}

private final class WritingScrollView: NSScrollView {
    var viewportChanged: (() -> Void)?
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        viewportChanged?()
    }

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
    /// A sheet can own keyboard focus while the parent retains its first responder.
    static func acceptsScriptCommands(in window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil else { return false }
        return window.firstResponder is WritingTextView
    }

    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }

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
    private var lineBreaks: NativeLineBreaks?
    private let wrappingValidator = NativeWrappingValidator()
    func setPagePlan(_ plan: PrintedWritingLayout?, invalidatedFrom: Int? = nil, updatedRange: NSRange? = nil) {
        if let id = plan?.id, attemptedPlanID == id, updatedRange == nil { return }
        let changedBreakStart = NativeLineBreaks.firstChange(from: lineBreaks, to: plan?.lineBreaks)
        let breaksChanged = changedBreakStart != nil
        if let storage = textStorage, let container = textContainer, let manager = layoutManager {
            wrappingValidator.update(from: storage, changedRange: updatedRange, container: container, manager: manager, lineBreaks: plan?.lineBreaks)
        }
        if let id = plan?.id, attemptedPlanID == id { return }
        lineBreaks = plan?.lineBreaks
        attemptedPlanID = plan?.id
        var start = 0
        if let previous = pagePlan, let plan, let invalidatedFrom {
            let changedLines = previous.lines.keys.filter { previous.lines[$0] != plan.lines[$0] }
                + plan.lines.keys.filter { previous.lines[$0] == nil }
            start = min(invalidatedFrom, changedLines.min() ?? invalidatedFrom)
            if let changedBreakStart { start = min(start, changedBreakStart) }
        }
        start = min(max(0, start), (string as NSString).length)
        let invalidated = NSRange(location: start, length: (string as NSString).length - start)
        // Validate wrapping in a separate retained TextKit layout, including any
        // experimental print-derived break opportunities. The displayed
        // editor only lays out paged coordinates, rather than laying out twice.
        layoutManager?.delegate = self
        if let plan, let manager = layoutManager, let container = textContainer {
            let starts = wrappingValidator.lineStarts()
            guard Set(plan.lines.keys).isSubset(of: starts) else {
                // Never draw a mixture of paged and continuous coordinates.
                let wasPaged = pagePlan != nil
                pagePlan = nil
                lineBreaks = nil
                if wasPaged || breaksChanged {
                    manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
                    manager.ensureLayout(for: container)
                } else {
                    // TextKit has already invalidated the edited paragraph. Repeated
                    // fallback must not force every offscreen paragraph to lay out.
                    let viewport = visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
                    manager.ensureLayout(forBoundingRect: viewport, in: container)
                }
                return
            }
            pagePlan = plan
            manager.invalidateLayout(forCharacterRange: invalidated, actualCharacterRange: nil)
            // The complete page plan already determines document height. Lay out
            // the viewport now; TextKit can resolve offscreen glyphs on demand.
            let viewport = visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
            if string.isEmpty || string.hasSuffix("\n") {
                // TextKit must finish its natural trailing fragment before we put
                // the blank-line caret at the printed page position below.
                manager.ensureLayout(for: container)
            } else {
                manager.ensureLayout(forBoundingRect: viewport, in: container)
            }
            if string.isEmpty || string.hasSuffix("\n"), let line = plan.lines[(string as NSString).length] {
                let rect = NSRect(x: 0, y: line.y * displayScale, width: container.containerSize.width, height: line.height * displayScale)
                manager.setExtraLineFragmentRect(rect, usedRect: rect, textContainer: container)
            }
            let size = NSSize(width: frame.width, height: (CGFloat(plan.labels.count) * PrintedWritingLayout.stride - 24) * displayScale)
            if frame.size != size { setFrameSize(size) }
        } else {
            pagePlan = nil
            layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
        }
    }
    func layoutManager(_ manager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt index: Int) -> Bool {
        lineBreaks?.allows(index) ?? true
    }
    func layoutManager(_ manager: NSLayoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt index: Int) -> Bool {
        lineBreaks?.allows(index) ?? true
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
        let redraw = rect.intersection(visibleRect)
        guard !redraw.isEmpty else { return }
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: StudioAppearance.courier(size: 12 * displayScale), .foregroundColor: guideInk]
        for (index, label) in plan.labels.enumerated() {
            let top = CGFloat(index) * PrintedWritingLayout.stride * displayScale
            let pageArea = NSRect(x: 0, y: top - 24 * displayScale, width: bounds.width, height: PrintedWritingLayout.stride * displayScale)
            guard pageArea.intersects(redraw) else { continue }
            if index > 0 {
                NSColor(calibratedWhite: 0.24, alpha: 1).setFill()
                NSRect(x: 0, y: top - 24 * displayScale, width: bounds.width, height: 24 * displayScale).fill()
            }
            (label + "." as String).draw(at: NSPoint(x: textContainerOrigin.x + 432 * displayScale, y: top + 36 * displayScale),
                withAttributes: labelAttributes)
        }
        for mark in plan.marks {
            var attrs = mark.attributes
            if let font = attrs[.font] as? NSFont { attrs[.font] = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * displayScale) }
            attrs[.foregroundColor] = guideInk
            let area = NSRect(x: textContainerOrigin.x + (mark.rect.minX - 108) * displayScale, y: mark.rect.minY * displayScale,
                width: mark.rect.width * displayScale, height: mark.rect.height * displayScale)
            if area.intersects(redraw) { mark.text.draw(in: area, withAttributes: attrs) }
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
        guard window != nil else {
            focusChanged?(false)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
    override func insertTab(_ sender: Any?) { cycleType?(true) }
    override func insertBacktab(_ sender: Any?) { cycleType?(false) }
}
