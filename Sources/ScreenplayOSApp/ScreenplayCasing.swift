import Foundation
import ScreenplayDomain

/// Presentation rules. Reading a screenplay never rewrites its authored text.
enum ScreenplayCasing {
    static func ranges(in elements: [ScreenplayElement]) -> [UUID: [NSRange]] {
        var result: [UUID: [NSRange]] = [:]
        for element in elements {
            if [.sceneHeading, .character, .transition, .shot].contains(element.type) {
                result[element.id] = [NSRange(location: 0, length: (element.text as NSString).length)]
            } else if element.type == .parenthetical,
                      element.text.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\((?:O\.S\.|V\.O\.|O\.C\.|CONT['’]D)\)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                result[element.id] = [NSRange(location: 0, length: (element.text as NSString).length)]
            }
        }
        // Known dialogue names identify first introductions; unknown names cannot be inferred safely.
        let names = Set(elements.filter { $0.type == .character }.map {
            $0.text.components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }.filter { !$0.isEmpty }).sorted { $0.count > $1.count }
        for name in names {
            let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for element in elements where element.type == .action {
                let length = (element.text as NSString).length
                if let match = regex.firstMatch(in: element.text, range: NSRange(location: 0, length: length)) {
                    result[element.id, default: []].append(match.range)
                    break
                }
            }
        }
        return result
    }
    static func render(_ text: String, ranges: [NSRange]) -> String {
        var offset = 0
        return text.map { character in
            let raw = String(character)
            defer { offset += (raw as NSString).length }
            return ranges.contains { NSLocationInRange(offset, $0) } ? raw.uppercased() : raw
        }.joined()
    }
}
