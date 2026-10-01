import Foundation
import ScreenplayDomain

/// Ephemeral links from printed text back to the canonical editor text.
/// Normalized print text is never used as an editable copy of the screenplay.
struct ScriptPrintProjection {
    struct SourceEntry {
        let elementID: UUID
        let type: ElementType
        let text: String
        let documentRange: NSRange
    }

    let pages: [ScreenplayPage]
    // Includes blank paragraphs and explicit breaks even when print omits them.
    let sourceEntries: [SourceEntry]
    let unmappedElementIDs: Set<UUID>

    init(pages: [ScreenplayPage], source: [ScreenplayElement]) {
        var offset = 0
        var entries: [SourceEntry] = []
        var maps: [UUID: TextMap] = [:]
        for element in source {
            let length = (element.text as NSString).length
            entries.append(SourceEntry(elementID: element.id, type: element.type, text: element.text,
                documentRange: NSRange(location: offset, length: length)))
            maps[element.id] = TextMap(element: element, documentOffset: offset)
            offset += length + 1 // The editor joins elements with one newline.
        }
        var consumed: [UUID: Int] = [:]
        var unmapped = Set<UUID>()
        self.pages = pages.map { page in
            let items = page.elements.map { item in
                var item = item
                item.sourceSpan = nil
                guard !item.isContinuation else { return item }
                let id = item.element.id
                let start = consumed[id, default: 0]
                let range = NSRange(location: start, length: (item.text as NSString).length)
                if let map = maps[id], let span = map.span(for: range, matching: item.text) {
                    item.sourceSpan = span
                    consumed[id] = NSMaxRange(range)
                } else {
                    // Never guess using a repeated phrase from another paragraph.
                    unmapped.insert(id)
                }
                return item
            }
            return ScreenplayPage(number: page.number, elements: items, lockedLabel: page.lockedLabel)
        }
        for entry in entries where entry.type != .pageBreak && !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let map = maps[entry.elementID], consumed[entry.elementID, default: 0] != (map.displayed as NSString).length {
                unmapped.insert(entry.elementID)
            }
        }
        sourceEntries = entries
        unmappedElementIDs = unmapped
    }

    /// Half-open spans assign a boundary caret to the following fragment.
    /// Unprinted blanks/breaks have no page; do not guess from a neighbouring scene.
    func pageIndex(containing offset: Int) -> Int? {
        guard unmappedElementIDs.isEmpty, offset >= 0,
              let entry = sourceEntries.last(where: { $0.documentRange.location <= offset }),
              offset <= NSMaxRange(entry.documentRange) else { return nil }
        var candidates: [(Int, NSRange)] = []
        for (index, page) in pages.enumerated() {
            for item in page.elements {
                if let span = item.sourceSpan, span.elementID == entry.elementID {
                    candidates.append((index, span.documentRange))
                }
            }
        }
        if let exact = candidates.first(where: { NSLocationInRange(offset, $0.1) }) { return exact.0 }
        // Leading/trailing whitespace belongs to this element's first/last printed fragment.
        guard let first = candidates.first, let last = candidates.last else { return nil }
        if offset < first.1.location { return first.0 }
        if offset >= NSMaxRange(last.1) { return last.0 }
        return nil
    }

    func firstSourceCaret(onPage index: Int) -> NSRange? {
        guard unmappedElementIDs.isEmpty, pages.indices.contains(index),
              let span = pages[index].elements.compactMap(\.sourceSpan).first else { return nil }
        return NSRange(location: span.documentRange.location, length: 0)
    }

    private struct TextMap {
        struct Segment {
            let displayed: NSRange
            let source: NSRange
        }
        let elementID: UUID
        let documentOffset: Int
        let displayed: String
        let segments: [Segment]
        let sourceLength: Int
        let directSourceStart: Int?

        init(element: ScreenplayElement, documentOffset: Int) {
            elementID = element.id
            self.documentOffset = documentOffset
            let original = element.text as NSString
            sourceLength = original.length
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = text.isEmpty ? 0 : original.range(of: text, options: .literal).location
            let uppercase = [.sceneHeading, .character, .transition, .shot].contains(element.type)
            directSourceStart = uppercase ? nil : start
            if !uppercase {
                displayed = text
                segments = []
                return
            }
            var output = "", segments: [Segment] = []
            var sourceOffset = start
            var displayOffset = 0
            for character in text {
                let raw = String(character)
                let rendered = uppercase ? raw.uppercased() : raw
                let rawLength = (raw as NSString).length
                let renderedLength = (rendered as NSString).length
                segments.append(Segment(displayed: NSRange(location: displayOffset, length: renderedLength),
                    source: NSRange(location: sourceOffset, length: rawLength)))
                output += rendered
                sourceOffset += rawLength
                displayOffset += renderedLength
            }
            displayed = output
            self.segments = segments
        }

        func span(for range: NSRange, matching text: String) -> PrintSourceSpan? {
            let output = displayed as NSString
            guard range.location >= 0, NSMaxRange(range) <= output.length,
                  output.substring(with: range) == text else { return nil }
            if range.length == 0 {
                guard sourceLength == 0 else { return nil }
                return PrintSourceSpan(elementID: elementID, elementRange: NSRange(location: 0, length: 0),
                    documentRange: NSRange(location: documentOffset, length: 0))
            }
            if let start = directSourceStart {
                guard Range(range, in: displayed) != nil else { return nil }
                let local = NSRange(location: start + range.location, length: range.length)
                return PrintSourceSpan(elementID: elementID, elementRange: local,
                    documentRange: NSRange(location: documentOffset + local.location, length: local.length))
            }
            guard let first = segments.first(where: { NSMaxRange($0.displayed) > range.location }),
                  let last = segments.last(where: { $0.displayed.location < NSMaxRange(range) }) else { return nil }
            // Expansions such as ß -> SS map to the complete authored grapheme.
            let local = NSRange(location: first.source.location, length: NSMaxRange(last.source) - first.source.location)
            return PrintSourceSpan(elementID: elementID, elementRange: local,
                documentRange: NSRange(location: documentOffset + local.location, length: local.length))
        }
    }
}

struct PrintSourceSpan: Equatable {
    let elementID: UUID
    let elementRange: NSRange
    let documentRange: NSRange
}
