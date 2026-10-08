import Foundation

/// Detects legacy JSON content that this build would not write back.
///
/// The legacy model decodes a fixed set of fields, so re-saving a file written by a
/// newer build or another tool would silently drop anything else. Callers use this
/// to open such files as unsaved copies instead of autosaving over the original.
public enum LegacyRoundTrip {
    /// Keys a supported migration intentionally rewrites under a new name.
    static let migratedKeys: Set<String> = ["post_enabled"]

    /// JSON paths present in `original` that would be missing after saving `document`.
    /// Null, false, and empty values are ignored: dropping them loses no authored content.
    public static func droppedPaths(original: Data, document: OpenScreenplayDocument) -> [String] {
        guard let raw = try? JSONSerialization.jsonObject(with: original),
              let encoded = try? JSONEncoder.openScreenplayEncoder().encode(document),
              let saved = try? JSONSerialization.jsonObject(with: encoded) else { return [] }
        var paths: [String] = []
        collect(raw, saved, path: "", into: &paths)
        return paths
    }

    private static func collect(_ raw: Any, _ saved: Any, path: String, into paths: inout [String]) {
        if let raw = raw as? [String: Any] {
            guard let saved = saved as? [String: Any] else { return }
            for key in raw.keys.sorted() {
                guard let value = raw[key] else { continue }
                let child = path.isEmpty ? key : path + "." + key
                if let kept = saved[key] {
                    collect(value, kept, path: child, into: &paths)
                } else if !migratedKeys.contains(key), carriesContent(value) {
                    paths.append(child)
                }
            }
        } else if let raw = raw as? [Any], let saved = saved as? [Any], raw.count == saved.count {
            for (index, pair) in zip(raw, saved).enumerated() {
                collect(pair.0, pair.1, path: "\(path)[\(index)]", into: &paths)
            }
        }
    }

    private static func carriesContent(_ value: Any) -> Bool {
        switch value {
        case is NSNull:
            return false
        case let string as String:
            return !string.isEmpty
        case let array as [Any]:
            return !array.isEmpty
        case let object as [String: Any]:
            return !object.isEmpty
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return true
        default:
            return true
        }
    }
}
