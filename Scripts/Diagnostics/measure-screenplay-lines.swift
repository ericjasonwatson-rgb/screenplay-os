// Run: swift Scripts/Diagnostics/measure-screenplay-lines.swift path/to/sample.fdx
// Read-only calibration harness. Does not alter application layout or source files.
import AppKit
import Foundation
import CoreText

final class ParagraphReader: NSObject, XMLParserDelegate {
    var paragraphs: [(String, String)] = []
    private var path: [String] = []
    private var type: String?, text = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        if path == ["FinalDraft", "Content", "Paragraph"] { type = attributes["Type"]; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path == ["FinalDraft", "Content", "Paragraph", "Text"] { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if path == ["FinalDraft", "Content", "Paragraph"], let type {
            paragraphs.append((type, text)); self.type = nil
        }
        path.removeLast()
    }
}
func measure(_ text: String, width: CGFloat, font: NSFont, mode: String) -> (Int, CGFloat, CGFloat) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    if mode == "legacy" { style.lineSpacing = 2 }
    if mode == "fixed12" { style.minimumLineHeight = 12; style.maximumLineHeight = 12 }
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    let storage = NSTextStorage(attributedString: attributed)
    let manager = NSLayoutManager(); storage.addLayoutManager(manager)
    let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0; manager.addTextContainer(container); manager.ensureLayout(for: container)
    var baselines: [CGFloat] = []
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, range, _ in
        baselines.append(rect.minY + manager.location(forGlyphAt: range.location).y)
    }
    let pitch = baselines.count > 1 ? (baselines.last! - baselines[0]) / CGFloat(baselines.count - 1) : 0
    let height = attributed.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    return (baselines.count, pitch, ceil(height))
}
// Optional locally installed reference font; register only within this process.
// Never copy or redistribute a proprietary font with the project.
if let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_REFERENCE_FONT"] {
    var error: Unmanaged<CFError>?
    guard CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error) else {
        fatalError("Reference font could not be registered: \(String(describing: error?.takeRetainedValue()))")
    }
}
let names = NSFontManager.shared.availableFonts.filter { $0.lowercased().contains("courier") }.sorted()
print("Available Courier faces: \(names.joined(separator: ", "))")
let fonts = ["Courier", "CourierFinalDraft", "Courier Final Draft"]
var seen: Set<String> = []
for name in fonts {
    guard let font = NSFont(name: name, size: 12), seen.insert(font.fontName).inserted else { continue }
    for mode in ["legacy", "natural", "fixed12"] {
        let probe = measure(Array(repeating: "Agyp 0123456789", count: 10).joined(separator: "\n"), width: 432, font: font, mode: mode)
        print("font=\(font.fontName) mode=\(mode) probeLines=\(probe.0) baselinePitch=\(probe.1) height=\(probe.2)")
        for path in CommandLine.arguments.dropFirst() {
            let reader = ParagraphReader()
            guard let parser = XMLParser(contentsOf: URL(fileURLWithPath: path)) else { fatalError("Cannot read \(path)") }
            parser.delegate = reader
            guard parser.parse(), !reader.paragraphs.isEmpty else { fatalError("Invalid or empty FDX: \(path)") }
            var lines = 0, rawHeight: CGFloat = 0, clampedHeight: CGFloat = 0
            for (type, text) in reader.paragraphs {
                let width: CGFloat = ["Dialogue":252, "Character":270, "Parenthetical":180, "Transition":115][type] ?? 432
                let m = measure(text.trimmingCharacters(in: .whitespacesAndNewlines), width: width, font: font, mode: mode)
                lines += m.0; rawHeight += m.2; clampedHeight += max(16, m.2)
            }
            print("  \(URL(fileURLWithPath: path).lastPathComponent): paragraphs=\(reader.paragraphs.count) lines=\(lines) textHeight=\(rawHeight) withLegacy16ptMinimum=\(clampedHeight)")
        }
    }
}
print("Heights exclude paragraph gaps, page splitting, continuation markers, and keep-together rules. They are not page counts. fixed12 is an experiment for 12-point fonts, not a released layout profile.")
