import AppKit
import ScreenplayDomain

/// Page placement derived from the same attributed fragments drawn by PDF export.
@MainActor
struct PrintedWritingLayout {
    let id = UUID()
    struct Line { let y: CGFloat; let height: CGFloat; let baseline: CGFloat }
    struct Mark { let text: String; let rect: NSRect; let attributes: [NSAttributedString.Key: Any] }
    let lines: [Int: Line]
    let marks: [Mark]
    let labels: [String]
    static let stride: CGFloat = 816

    init?(print projection: ScriptPrintProjection, writing: ScreenplayWritingProjection, typography: DocumentTypography) {
        guard projection.unmappedElementIDs.isEmpty else { return nil }
        var lines: [Int: Line] = [:], marks: [Mark] = []
        for (pageIndex, page) in projection.pages.enumerated() {
            var y = CGFloat(pageIndex) * Self.stride
            for item in page.elements {
                y += item.layout.before
                let attrs: [NSAttributedString.Key: Any] = [.font: PackageTypography.font(typography),
                    .paragraphStyle: ScreenplayBodyLayout.textStyle(alignment: item.layout.alignment)]
                if item.isContinuation {
                    marks.append(Mark(text: item.text, rect: NSRect(x: item.layout.x, y: y + 72, width: item.layout.width, height: item.textHeight + 4), attributes: attrs))
                } else if let span = item.sourceSpan {
                    let range = writing.displayRange(span.documentRange)
                    guard NSMaxRange(range) <= (writing.text as NSString).length,
                          (writing.text as NSString).substring(with: range) == item.text else { return nil }
                    let storage = NSTextStorage(attributedString: item.attributed ?? NSAttributedString(string: item.text, attributes: attrs))
                    let manager = NSLayoutManager(); storage.addLayoutManager(manager)
                    let area = NSTextContainer(size: NSSize(width: item.layout.width, height: .greatestFiniteMagnitude))
                    area.lineFragmentPadding = 0; manager.addTextContainer(area); manager.ensureLayout(for: area)
                    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: area)) { rect, _, _, glyphs, _ in
                        let start = range.location + manager.characterIndexForGlyph(at: glyphs.location)
                        lines[start] = Line(y: y + rect.minY, height: rect.height, baseline: manager.location(forGlyphAt: glyphs.location).y)
                    }
                    if item.text.isEmpty {
                        lines[range.location] = Line(y: y, height: item.textHeight, baseline: PackageTypography.font(typography).ascender)
                    }
                }
                y += item.textHeight + item.layout.after
            }
        }
        self.lines = lines; self.marks = marks; labels = projection.pages.map(\.label)
    }
}
