import AppKit
import SwiftUI
import ScreenplayDomain

/// Read-only scene text using the writing surface's exact paragraph renderer.
/// Narrow panes scroll the page instead of reflowing screenplay margins.
struct SceneScreenplayPreview: NSViewRepresentable {
    @ObservedObject var model: ScreenplayViewModel
    @MainActor final class Coordinator {
        let renderer = WritingTextRenderCache()
        var sceneID: UUID?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.isVerticallyResizable = false
        text.isHorizontallyResizable = false
        text.textContainerInset = NSSize(width: 90, height: 72)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.containerSize = NSSize(width: ScreenplayBodyLayout.textWidth, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage,
              let layout = text.layoutManager, let container = text.textContainer else { return }
        let elements = model.selectedSceneScriptElements
        let projection = ScreenplayWritingProjection(elements: elements, casing: model.screenplayCasing)
        _ = context.coordinator.renderer.update(storage, elements: elements, projection: projection,
            typography: model.writingTypography, dark: model.darkPageMode, selectedID: nil, nativeEdit: nil)
        text.backgroundColor = StudioAppearance.paper(model.darkPageMode)
        scroll.backgroundColor = text.backgroundColor
        layout.ensureLayout(for: container)
        text.setFrameSize(NSSize(width: 612, height: max(792, layout.usedRect(for: container).height + 144)))
        if scroll.magnification != model.pageZoom { scroll.setMagnification(model.pageZoom, centeredAt: .zero) }
        if context.coordinator.sceneID != elements.first?.id {
            context.coordinator.sceneID = elements.first?.id
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
