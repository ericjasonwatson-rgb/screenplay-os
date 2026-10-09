import Foundation

/// Experimental preference only. Never invent a native line start or alter text.
/// Interior sentence endings require a coordinated typesetter and remain deferred.
enum SentenceAlignedSplit {
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
