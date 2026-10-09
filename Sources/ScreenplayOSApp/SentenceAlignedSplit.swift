import Foundation

/// Experimental sentence preferences return source prefixes, never rewritten text.
/// Interior sentence endings are opt-in and require a matching native line plan.
enum SentenceAlignedSplit {
    static func preferredInteriorEnd(in text: String, fittingLineEnds: [Int]) -> Int {
        guard let fallback = fittingLineEnds.last else { return 0 }
        guard fittingLineEnds.count >= 2, let firstLineEnd = fittingLineEnds.first else { return fallback }
        let source = text as NSString
        var preferred: Int?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.bySentences, .substringNotRequired]) { _, _, enclosing, stop in
            let end = NSMaxRange(NSRange(enclosing, in: text))
            if end > fallback { stop = true; return }
            // Keep two lines, and require a normal word-break opportunity. Never
            // split a grapheme, force a hyphen, or invent a source separator.
            if end > firstLineEnd, end < source.length, source.character(at: end - 1) == 32 {
                preferred = end
            }
        }
        return preferred ?? fallback
    }

    static func preferredEnd(in text: String, fittingLineEnds: [Int]) -> Int {
        guard let fallback = fittingLineEnds.last else { return 0 }
        guard fittingLineEnds.count >= 2 else { return fallback }
        let eligible = Set(fittingLineEnds.dropFirst())
        var preferred: Int?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.bySentences, .substringNotRequired]) { _, _, enclosing, stop in
            let end = NSMaxRange(NSRange(enclosing, in: text))
            if end > fallback { stop = true; return }
            if eligible.contains(end) { preferred = end }
        }
        return preferred ?? fallback
    }
}
