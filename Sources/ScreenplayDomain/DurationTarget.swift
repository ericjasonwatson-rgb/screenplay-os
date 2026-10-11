import Foundation

/// Authored planning seconds, independent of estimated or measured runtime.
public enum DurationTarget {
    public static func isValid(_ seconds: Int) -> Bool { (1...86_400).contains(seconds) }

    /// Accept whole seconds or minutes:seconds. Blank is handled explicitly as clearing by the caller.
    public static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let first = Int(parts[0]), first <= 86_400 else { return nil }
        let value: Int
        if parts.count == 2 {
            guard parts[1].count == 2, let seconds = Int(parts[1]), seconds < 60 else { return nil }
            value = first * 60 + seconds
        } else { value = first }
        return isValid(value) ? value : nil
    }

    public static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

public extension ScreenplayOSDocument {
    /// Apply authored intent only. History, save, and UI are owned by the caller.
    @discardableResult mutating func setSceneDurationTarget(headingID: UUID, seconds: Int?) -> Bool {
        guard screenplay.elements.contains(where: { $0.id == headingID && $0.type == .sceneHeading }),
              seconds.map(DurationTarget.isValid) ?? true else { return false }
        var targets = sceneDurationTargets ?? [:]
        targets[headingID.uuidString] = seconds
        sceneDurationTargets = targets.isEmpty ? nil : targets
        return true
    }

    @discardableResult mutating func setOutlineDurationTarget(beatID: UUID, seconds: Int?) -> Bool {
        guard let index = outline.firstIndex(where: { $0.id == beatID }),
              seconds.map(DurationTarget.isValid) ?? true else { return false }
        outline[index].targetDurationSeconds = seconds
        return true
    }
}
