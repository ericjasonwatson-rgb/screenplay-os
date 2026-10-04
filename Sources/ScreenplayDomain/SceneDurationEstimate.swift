import Foundation

/// A planning heuristic, not measured performance. Never changes authored data or persisted clip timing.
public struct SceneDurationEstimate: Equatable {
    public let minimumSeconds: Double
    public let maximumSeconds: Double

    public init?(elements: [ScreenplayElement]) {
        var dialogue = 0, action = 0
        for element in elements {
            let words = element.text.split(whereSeparator: { $0.isWhitespace }).count
            if element.type == .dialogue { dialogue += words }
            if element.type == .action { action += words }
        }
        guard dialogue + action > 0 else { return nil }
        // Deliberately broad, explicit assumptions: speech 120–180 words/minute;
        // action prose 60–120 words/minute. Action may take much longer on screen.
        minimumSeconds = max(5, floor((Double(dialogue) / 3 + Double(action) / 2) / 5) * 5)
        maximumSeconds = max(minimumSeconds + 5, ceil((Double(dialogue) / 2 + Double(action)) / 5) * 5)
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
