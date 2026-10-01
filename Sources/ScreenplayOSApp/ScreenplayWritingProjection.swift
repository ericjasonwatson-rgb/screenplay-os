import Foundation
import ScreenplayDomain

/// Display-only heading capitalization. Source text and UTF-16 selections remain authoritative.
struct ScreenplayWritingProjection {
    struct Segment {
        let source: NSRange
        let display: NSRange
    }
    let text: String
    let ranges: [NSRange]
    private let segments: [Segment]
    private let sourceLength: Int

    init(elements: [ScreenplayElement]) {
        var output = "", ranges: [NSRange] = [], segments: [Segment] = []
        var sourceOffset = 0, displayOffset = 0
        for (index, element) in elements.enumerated() {
            let start = displayOffset
            // Ordinary paragraphs need one identity span, not a record per character.
            let pieces = element.type == .sceneHeading && element.text != element.text.uppercased()
                ? element.text.map(String.init) : [element.text]
            for raw in pieces where !raw.isEmpty {
                let shown = element.type == .sceneHeading ? raw.uppercased() : raw
                let sourceCount = (raw as NSString).length, displayCount = (shown as NSString).length
                segments.append(Segment(source: NSRange(location: sourceOffset, length: sourceCount),
                    display: NSRange(location: displayOffset, length: displayCount)))
                output += shown; sourceOffset += sourceCount; displayOffset += displayCount
            }
            ranges.append(NSRange(location: start, length: displayOffset - start))
            if index < elements.count - 1 {
                segments.append(Segment(source: NSRange(location: sourceOffset, length: 1),
                    display: NSRange(location: displayOffset, length: 1)))
                output += "\n"; sourceOffset += 1; displayOffset += 1
            }
        }
        text = output; self.ranges = ranges; self.segments = segments; sourceLength = sourceOffset
    }

    func sourceRange(_ range: NSRange) -> NSRange { map(range, toDisplay: false) }
    func displayRange(_ range: NSRange) -> NSRange { map(range, toDisplay: true) }

    private func map(_ range: NSRange, toDisplay: Bool) -> NSRange {
        let limit = toDisplay ? (text as NSString).length : sourceLength
        func boundary(_ offset: Int, trailing: Bool) -> Int {
            // Half-open spans make exact boundaries belong to the next character.
            var lower = 0, upper = segments.count
            while lower < upper {
                let middle = (lower + upper) / 2
                let r = toDisplay ? segments[middle].source : segments[middle].display
                if NSMaxRange(r) <= offset { lower = middle + 1 } else { upper = middle }
            }
            guard lower < segments.count else { return limit }
            let segment = segments[lower]
            let from = toDisplay ? segment.source : segment.display
            let to = toDisplay ? segment.display : segment.source
            if offset <= from.location { return to.location }
            if from.length == to.length { return to.location + offset - from.location }
            return trailing ? NSMaxRange(to) : to.location
        }
        let start = boundary(range.location, trailing: false)
        let end = range.length == 0 ? start : boundary(NSMaxRange(range), trailing: true)
        return NSRange(location: start, length: max(0, end - start))
    }
}
