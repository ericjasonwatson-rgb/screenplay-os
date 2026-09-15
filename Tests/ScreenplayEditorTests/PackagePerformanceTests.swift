import AppKit
import SwiftUI
import Testing
@testable import ScreenplayOSApp

@Suite("Package typing measurement", .serialized)
@MainActor
struct PackagePerformanceTests {
    @Test func measureWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["PACKAGE_BENCHMARK"] == "1" else { return }
        _ = NSApplication.shared
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = source.appendingPathComponent("screenplay.json")
        var script = try JSONSerialization.jsonObject(with: Data(contentsOf: scriptURL)) as! [String: Any]
        script["elements"] = (0..<1200).map { i in ["id": UUID().uuidString, "type": i % 4 == 0 ? "scene_heading" : "action", "text": "Paragraph \(i). " + String(repeating: "A writer follows the scene through the quiet room. ", count: 3)] }
        try JSONSerialization.data(withJSONObject: script).write(to: scriptURL)
        let editor = try PackageEditor(source: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let host = NSHostingView(rootView: PackageEditorView(editor: editor, close: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func find(_ view: NSView) -> NSTextView? { if let text = view as? NSTextView { return text }; return view.subviews.lazy.compactMap { find($0) }.first }
        window.orderFront(nil); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let text = try #require(find(host))
        var timings: [Double] = []
        let location = ProcessInfo.processInfo.environment["PACKAGE_BENCHMARK_LOCATION"] ?? "end"
        let startOffset = location == "start" ? 0 : location == "middle" ? (text.string as NSString).length / 2 : (text.string as NSString).length
        for i in 0..<10 {
            text.setSelectedRange(NSRange(location: startOffset + i, length: 0))
            let start = Date()
            text.insertText("x", replacementRange: text.selectedRange())
            host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.001)); host.displayIfNeeded()
            timings.append(Date().timeIntervalSince(start) * 1000)
            #expect(text.string == PackageWritingProjection(editor.session).text)
        }
        print("PACKAGE_BENCHMARK_LOCATION=\(location)")
        print("PACKAGE_TYPING_MS=\(timings)")
        #expect(editor.flushRecovery())
    }
}
