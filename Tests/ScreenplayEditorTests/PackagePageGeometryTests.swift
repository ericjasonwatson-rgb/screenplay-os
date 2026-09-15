import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Shared screenplay geometry", .serialized) @MainActor
struct PackagePageGeometryTests {
    @Test func nativeLinesMatchPrintAcrossFontsTypesAndWindowWidths() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var session = try PackageEditedCopy.load(source)
        for paragraph in session.paragraphs { try session.delete(elementID: paragraph.id, expectedRevision: session.revision) }
        for type in PackageTextSession.supportedTypes {
            let id = try session.insert(after: session.paragraphs.last?.id, expectedRevision: session.revision, type: type,
                text: "The quiet room holds a long line of ordinary words, with punctuation and café, repeated until this paragraph wraps naturally around the page.")
            try session.format(elementID: id, expectedRevision: session.revision, range: 4..<14, patch: .init(bold: true, italic: true))
        }
        try session.screenplayBytes.write(to: source.appendingPathComponent("screenplay.json"))
        let editor = try PackageEditor(source: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let host = NSHostingView(rootView: PackageParagraphTextView(editor: editor))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap { find($0) }.first }
        refresh()
        let text = try #require(find(host))
        for font in ["Courier", "Helvetica"] {
            for size in [12.0, 16.0, 24.0] {
                editor.changeTypography(font: font, size: size); refresh()
                let printed = try PackagePrintLayout.make(editor.session)
                for width in [900.0, 420.0] {
                    window.setContentSize(NSSize(width: width, height: 600)); refresh()
                    let layout = try #require(text.layoutManager), area = try #require(text.textContainer)
                    layout.ensureLayout(for: area)
                    var lines: [NSRange] = []
                    layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: area)) { _, _, _, range, _ in
                        lines.append(layout.characterRange(forGlyphRange: range, actualGlyphRange: nil))
                    }
                    #expect(area.containerSize.width == 432)
                    #expect(text.frame.width == 612)
                    #expect(text.textContainerOrigin.x == 108)
                    #expect(lines == printed.lineCharacterRanges, "\(font) \(size) at window width \(width)")
                }
            }
        }
    }
}
