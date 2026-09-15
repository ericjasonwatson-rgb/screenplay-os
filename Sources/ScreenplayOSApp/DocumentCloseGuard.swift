import AppKit
import SwiftUI

/// Preserve SwiftUI's window delegate while intercepting user-initiated closes.
struct DocumentCloseGuard: NSViewRepresentable {
    let model: ScreenplayViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }
    func updateNSView(_ nsView: WindowProbe, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }
    static func dismantleNSView(_ nsView: WindowProbe, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class WindowProbe: NSView {
        var windowChanged: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChanged?(window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        let model: ScreenplayViewModel
        weak var window: NSWindow?
        weak var originalDelegate: NSWindowDelegate?
        init(model: ScreenplayViewModel) { self.model = model }

        func attach(to newWindow: NSWindow?) {
            if window === newWindow { return }
            if window?.delegate === self { window?.delegate = originalDelegate }
            window = newWindow
            DispatchQueue.main.async { [weak self, weak newWindow] in self?.model.legacyWindow = newWindow }
            originalDelegate = newWindow?.delegate
            newWindow?.delegate = self
        }

        func windowDidBecomeKey(_ notification: Notification) {
            model.legacyWindow = window
            model.packageEditor = nil
            originalDelegate?.windowDidBecomeKey?(notification)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard model.confirmSafeClose(includePackages: false) else { return false }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}
