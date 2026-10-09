import Foundation

/// Read-only line-break opportunities measured from print fragments. Restrict only
/// split dialogue paragraphs; all other text keeps normal TextKit wrapping.
struct NativeLineBreaks: Equatable {
    let starts: Set<Int>
    let paragraphs: [NSRange]

    init(starts: Set<Int>, paragraphs: [NSRange]) {
        self.paragraphs = paragraphs.sorted { $0.location < $1.location }
        self.starts = Set(starts.filter { offset in
            paragraphs.contains { NSLocationInRange(offset, $0) }
        })
    }

    func allows(_ offset: Int) -> Bool {
        var low = 0, high = paragraphs.count
        while low < high {
            let middle = (low + high) / 2
            if paragraphs[middle].location <= offset { low = middle + 1 }
            else { high = middle }
        }
        return low == 0 || !NSLocationInRange(offset, paragraphs[low - 1]) || starts.contains(offset)
    }

    /// Compare unaffected paragraphs in the new document's coordinate space.
    /// The edited paragraphs are remeasured by TextKit independently of policy.
    func outsideEdit(_ paragraphsChanged: NSRange, shiftingSuffixBy delta: Int = 0) -> Self {
        let end = NSMaxRange(paragraphsChanged)
        let ranges = paragraphs.compactMap { range -> NSRange? in
            if NSMaxRange(range) <= paragraphsChanged.location { return range }
            if range.location >= end { return NSRange(location: range.location + delta, length: range.length) }
            return nil
        }
        let offsets = Set(starts.compactMap { offset -> Int? in
            if offset < paragraphsChanged.location { return offset }
            if offset >= end { return offset + delta }
            return nil
        })
        return Self(starts: offsets, paragraphs: ranges)
    }

    /// Conservative earliest affected paragraph, in either old or new coordinates.
    /// Offsets before this point retain exactly the same break opportunities.
    static func firstChange(from old: Self?, to new: Self?) -> Int? {
        guard old != new else { return nil }
        let oldRanges = Set(old?.paragraphs ?? [])
        let newRanges = Set(new?.paragraphs ?? [])
        let rangeStart = oldRanges.symmetricDifference(newRanges).map(\.location).min()
        let changedStarts = (old?.starts ?? []).symmetricDifference(new?.starts ?? [])
        let lineStart = (oldRanges.union(newRanges)).filter { range in
            changedStarts.contains { NSLocationInRange($0, range) }
        }.map(\.location).min()
        return [rangeStart, lineStart].compactMap { $0 }.min()
    }
}
