import AppKit
import ScreenplayDomain

/// Page placement derived from the same attributed fragments drawn by PDF export.
@MainActor
struct PrintedWritingLayout {
    let id = UUID()
    struct Line: Equatable { let y: CGFloat; let height: CGFloat; let baseline: CGFloat }
    struct Mark { let text: String; let rect: NSRect; let attributes: [NSAttributedString.Key: Any] }
    final class MeasurementCache {
        struct Key: Hashable { let text: String; let width: CGFloat }
        struct Entry { let text: NSAttributedString; let lines: [(Int, Line)] }
        var entries: [Key: Entry] = [:]
    }
    let lines: [Int: Line]
    let lineBreaks: NativeLineBreaks?
    let marks: [Mark]
    let labels: [String]
    static let stride: CGFloat = 816

    init?(print projection: ScriptPrintProjection, writing: ScreenplayWritingProjection, typography: DocumentTypography, cache: MeasurementCache? = nil, lineLayout: ScreenplayLineLayout = .legacy) {
        guard projection.unmappedElementIDs.isEmpty else { return nil }
        var lines: [Int: Line] = [:], marks: [Mark] = []
        var seen = Set<UUID>(), splitDialogue = Set<UUID>()
        var nextMeasurements: [MeasurementCache.Key: MeasurementCache.Entry] = [:]
        for (pageIndex, page) in projection.pages.enumerated() {
            var y = CGFloat(pageIndex) * Self.stride
            for item in page.elements {
                y += item.layout.before
                var attrs: [NSAttributedString.Key: Any] = [.font: PackageTypography.font(typography),
                    .paragraphStyle: ScreenplayBodyLayout.textStyle(alignment: item.layout.alignment, lineLayout: lineLayout)]
                if let spacing = lineLayout.characterSpacing { attrs[.kern] = spacing }
                if item.isContinuation {
                    marks.append(Mark(text: item.text, rect: NSRect(x: item.layout.x, y: y + 72, width: item.layout.width, height: item.textHeight + 4), attributes: attrs))
                } else if let span = item.sourceSpan {
                    if lineLayout == .sentenceBoundaryExperiment, item.element.type == .dialogue,
                       !seen.insert(span.elementID).inserted { splitDialogue.insert(span.elementID) }
                    let range = writing.displayRange(span.documentRange)
                    guard NSMaxRange(range) <= (writing.text as NSString).length,
                          (writing.text as NSString).substring(with: range) == item.text else { return nil }
                    let attributed = item.attributed ?? NSAttributedString(string: item.text, attributes: attrs)
                    let key = MeasurementCache.Key(text: item.text, width: item.layout.width)
                    let measurement: MeasurementCache.Entry
                    if let existing = nextMeasurements[key] ?? cache?.entries[key], existing.text.isEqual(to: attributed) {
                        measurement = existing
                    } else {
                        let storage = NSTextStorage(attributedString: attributed)
                        let manager = NSLayoutManager(); storage.addLayoutManager(manager)
                        let area = NSTextContainer(size: NSSize(width: item.layout.width, height: .greatestFiniteMagnitude))
                        area.lineFragmentPadding = 0; manager.addTextContainer(area); manager.ensureLayout(for: area)
                        var measured: [(Int, Line)] = []
                        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: area)) { rect, _, _, glyphs, _ in
                            measured.append((manager.characterIndexForGlyph(at: glyphs.location),
                                Line(y: rect.minY, height: rect.height, baseline: manager.location(forGlyphAt: glyphs.location).y)))
                        }
                        measurement = MeasurementCache.Entry(text: attributed.copy() as! NSAttributedString, lines: measured)
                    }
                    nextMeasurements[key] = measurement
                    for (offset, line) in measurement.lines {
                        lines[range.location + offset] = Line(y: y + line.y, height: line.height, baseline: line.baseline)
                    }
                    if item.text.isEmpty {
                        lines[range.location] = Line(y: y, height: item.textHeight, baseline: PackageTypography.font(typography).ascender)
                    }
                }
                y += item.textHeight + item.layout.after
            }
        }
        cache?.entries = nextMeasurements
        self.lines = lines; self.marks = marks; labels = projection.pages.map(\.label)
        if lineLayout == .sentenceBoundaryExperiment, !splitDialogue.isEmpty {
            lineBreaks = NativeLineBreaks(starts: Set(lines.keys), paragraphs: projection.sourceEntries
                .filter { splitDialogue.contains($0.elementID) }.map { writing.displayRange($0.documentRange) })
        } else { lineBreaks = nil }
    }
}
