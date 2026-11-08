import AppKit
@testable import ScreenplayOSApp

/// Wait for an observable native result rather than assuming a task suspension
/// committed SwiftUI's AppKit hierarchy. Layout, display, and run-loop observers
/// all participate in that commit. The deadline is a failure bound, not a delay.
@MainActor
func waitForNativeUI(_ host: NSView, timeout: TimeInterval = 3,
                     until condition: @MainActor () -> Bool) async throws -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    repeat {
        nativeUILayoutPass(host)
        if condition() { return true }
        try await Task.sleep(nanoseconds: 10_000_000)
    } while ProcessInfo.processInfo.systemUptime < deadline
    nativeUILayoutPass(host)
    return condition()
}

@MainActor
private func nativeUILayoutPass(_ host: NSView) {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
}

/// Opt-in evidence for hosted SwiftUI/AppKit lifecycle failures. This does not
/// change layout, wait for a result, or filter the assertions under investigation.
@MainActor
func nativeUIHierarchyDiagnostic(_ stage: String, host: NSView, window: NSWindow, model: ScreenplayViewModel) {
    guard ProcessInfo.processInfo.environment["SCREENPLAYOS_NATIVE_UI_DIAGNOSTICS"] == "1" else { return }
    print("NATIVE_UI_DIAGNOSTIC BEGIN \(stage)")
    print("window visible=\(window.isVisible) key=\(window.isKeyWindow) firstResponder=\(String(describing: window.firstResponder))")
    print("model workflow=\(model.workflowMode) workspaceSignal=\(model.chromeState.signal(for: .workspace, model: model).value) contactCount=\(model.titlePage.contact.count)")
    if stage.hasPrefix("title") {
        do {
            let data = try model.makeTitlePagePDF()
            print("title export success bytes=\(data.count)")
        } catch {
            print("title export error=\(error) description=\(error.localizedDescription)")
        }
    }

    func describeViews(_ view: NSView, path: String) {
        print("VIEW \(path) \(type(of: view)) id=\(ObjectIdentifier(view)) windowMatches=\(view.window === window) hidden=\(view.isHidden) hiddenAncestor=\(view.isHiddenOrHasHiddenAncestor) alpha=\(view.alphaValue) frame=\(view.frame) visibleRect=\(view.visibleRect) role=\(String(describing: view.accessibilityRole())) label=\(String(describing: view.accessibilityLabel()))")
        if let canvas = view as? TitlePagePDFCanvas {
            print("PDF \(path) pageCount=\(String(describing: canvas.document?.pageCount)) text=\(String(describing: canvas.document?.string?.prefix(160)))")
        }
        if let editor = view as? WritingTextView {
            print("EDITOR \(path) editable=\(editor.isEditable) selectable=\(editor.isSelectable) firstResponder=\(window.firstResponder === editor) textCount=\((editor.string as NSString).length)")
        }
        for (index, child) in view.subviews.enumerated() {
            describeViews(child, path: "\(path).\(index)")
        }
    }
    describeViews(host, path: "host")

    var visited = Set<ObjectIdentifier>()
    var remaining = 400
    func describeAccessibility(_ value: Any, path: String, depth: Int = 0) {
        guard depth < 30, remaining > 0, let element = value as? NSAccessibilityProtocol else { return }
        let identity = ObjectIdentifier(element as AnyObject)
        guard visited.insert(identity).inserted else { return }
        remaining -= 1
        let children = element.accessibilityChildren() ?? []
        let label = String(describing: element.accessibilityLabel()).prefix(240)
        let value = String(describing: element.accessibilityValue()).prefix(240)
        print("AX \(path) \(type(of: element)) id=\(identity) element=\(element.isAccessibilityElement()) role=\(String(describing: element.accessibilityRole())) label=\(label) value=\(value) frame=\(element.accessibilityFrame()) children=\(children.count)")
        for (index, child) in children.enumerated() {
            describeAccessibility(child, path: "\(path).\(index)", depth: depth + 1)
        }
    }
    describeAccessibility(host, path: "host")
    describeAccessibility(window, path: "window")
    print("NATIVE_UI_DIAGNOSTIC END \(stage)")
}
