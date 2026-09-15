import AppKit
import Combine
import SwiftUI

/// Native presentation only; each editor retains its own selection, history and save baseline.
@MainActor
final class PackageWindows {
    weak var model: ScreenplayViewModel?
    private(set) var controllers: [PackageWindowController] = []
    init(model: ScreenplayViewModel) { self.model = model }

    func existing(at url: URL) -> PackageWindowController? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return controllers.first { $0.editor.currentURL?.standardizedFileURL.resolvingSymlinksInPath().path == path }
    }
    func present(_ editor: PackageEditor, show: Bool = true) {
        if let url = editor.currentURL, let existing = existing(at: url) {
            if show { existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil) }; return
        }
        let controller = PackageWindowController(editor: editor, owner: self)
        controllers.append(controller)
        if show { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil) }
        model?.packageEditor = editor
    }
    func removed(_ controller: PackageWindowController) {
        controllers.removeAll { $0 === controller }
        if model?.packageEditor === controller.editor { model?.packageEditor = nil }
        model?.refreshPackageRecoveries()
    }
    func confirmAll() -> Bool {
        for controller in controllers {
            if controller.editor.dirty { controller.window?.makeKeyAndOrderFront(nil) }
            if !controller.editor.confirmClose() { return false }
        }
        return true
    }
}

@MainActor
final class PackageWindowController: NSWindowController, NSWindowDelegate {
    let editor: PackageEditor
    weak var registry: PackageWindows?
    private var changes: AnyCancellable?
    init(editor: PackageEditor, owner: PackageWindows) {
        self.editor = editor; self.registry = owner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: PackageEditorView(editor: editor) { [weak self] in self?.window?.performClose(nil) })
        window.minSize = NSSize(width: 780, height: 580)
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat(owner.controllers.count % 6) * 24,
                                      y: window.frame.minY - CGFloat(owner.controllers.count % 6) * 24))
        updateTitle()
        changes = editor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateTitle() {
        window?.title = editor.currentURL?.lastPathComponent ?? "Untitled Screenplay"
        window?.representedURL = editor.currentURL
        window?.isDocumentEdited = editor.dirty
    }
    func windowDidBecomeKey(_ notification: Notification) {
        registry?.model?.packageEditor = editor
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isKeyWindow,
                  window.firstResponder === window else { return }
            func scriptView(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView, !text.isFieldEditor { return text }
                return view.subviews.lazy.compactMap { scriptView($0) }.first
            }
            if let content = window.contentView, let text = scriptView(content) { window.makeFirstResponder(text) }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { editor.confirmClose() }
    func windowWillClose(_ notification: Notification) { registry?.removed(self) }
}
