import Foundation

/// A planning heuristic, not measured performance. Never changes authored data or persisted clip timing.
public struct SceneDurationEstimate: Equatable {
    public let minimumSeconds: Double
    public let maximumSeconds: Double

    public init?(elements: [ScreenplayElement]) {
        var dialogue = 0, actionLines = 0
        for element in elements {
            let words = element.text.split(whereSeparator: { $0.isWhitespace }).count
            if element.type == .dialogue { dialogue += words }
            if element.type == .action, words > 0 { actionLines += Self.planningLines(element.text) + 1 }
        }
        guard dialogue + actionLines > 0 else { return nil }
        // A fixed planning page, independent of zoom/font/pagination: 60 columns,
        // 54 lines including paragraph spacing. One action page centers on 60s,
        // with a 45–75s band. This is a heuristic, not a performance prediction.
        let actionPages = Double(actionLines) / 54
        minimumSeconds = max(5, floor((Double(dialogue) / 3 + actionPages * 45) / 5) * 5)
        maximumSeconds = max(minimumSeconds + 5, ceil((Double(dialogue) / 2 + actionPages * 75) / 5) * 5)
    }

    private static func planningLines(_ text: String) -> Int {
        var lines = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let words = line.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty else { lines += 1; continue }
            var used = 0
            for word in words {
                let length = word.count
                if used > 0, used + 1 + length <= 60 { used += 1 + length }
                else {
                    if used > 0 { lines += 1 }
                    lines += (length - 1) / 60
                    used = (length - 1) % 60 + 1
                }
            }
            if used > 0 { lines += 1 }
        }
        return lines
    }

    public static func byScene(in elements: [ScreenplayElement]) -> [String: SceneDurationEstimate] {
        var result: [String: SceneDurationEstimate] = [:]
        var start: Int?
        func append(until end: Int) {
            guard let start, let id = elements[start].spineID,
                  let estimate = SceneDurationEstimate(elements: Array(elements[start..<end])) else { return }
            result[id] = estimate
        }
        for index in elements.indices where elements[index].type == .sceneHeading {
            append(until: index)
            start = index
        }
        append(until: elements.count)
        return result
    }
}

/// Ephemeral derived cache: reuses estimates for unchanged scenes while preserving
/// the same result as a fresh byScene pass after splits, merges, moves or deletion.
public struct SceneDurationEstimateCache {
    private var scenes: [UUID: (source: [ScreenplayElement], estimate: SceneDurationEstimate?)] = [:]
    public init() {}

    public mutating func estimates(in elements: [ScreenplayElement]) -> [String: SceneDurationEstimate] {
        var next: [UUID: (source: [ScreenplayElement], estimate: SceneDurationEstimate?)] = [:]
        var result: [String: SceneDurationEstimate] = [:]
        let starts = elements.indices.filter { elements[$0].type == .sceneHeading }
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1] : elements.count
            let heading = elements[start]
            let source = Array(elements[start..<end])
            let estimate: SceneDurationEstimate?
            if let prior = scenes[heading.id], prior.source == source { estimate = prior.estimate }
            else { estimate = SceneDurationEstimate(elements: source) }
            next[heading.id] = (source, estimate)
            if let id = heading.spineID, let estimate { result[id] = estimate }
        }
        scenes = next
        return result
    }
}
