import Foundation

/// Read-only, offline interchange manifest. It does not change the canonical project or resolve media.
enum MediaInterchangeManifest {
    struct Occurrence: Codable, Equatable {
        let occurrenceID: UUID
        let sceneID: UUID
        let shotID: UUID
        let boardID: UUID?
        let mediaPath: String?
        let startFrame: Int
        let durationFrames: Int
        let note: String
    }

    struct MissingMedia: Codable, Equatable {
        let occurrenceID: UUID
        let path: String
    }

    struct Manifest: Codable, Equatable {
        let formatVersion: Int
        let occurrences: [Occurrence]
        let missingMedia: [MissingMedia]
    }

    enum ValidationError: Error, Equatable {
        case duplicateOccurrence
        case invalidTiming
        case unsafePath
    }

    static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"),
              !path.contains("\\"), !path.contains("://"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            return false
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }
    }

    /// Callers supply a local existence predicate; this function performs no filesystem or network IO.
    static func make(_ occurrences: [Occurrence], mediaExists: (String) -> Bool) throws -> Manifest {
        var ids = Set<UUID>()
        var missing: [MissingMedia] = []
        for item in occurrences {
            guard ids.insert(item.occurrenceID).inserted else { throw ValidationError.duplicateOccurrence }
            guard item.startFrame >= 0, item.durationFrames > 0,
                  item.startFrame <= Int.max - item.durationFrames else { throw ValidationError.invalidTiming }
            if let path = item.mediaPath {
                guard safeRelativePath(path) else { throw ValidationError.unsafePath }
                if !mediaExists(path) { missing.append(MissingMedia(occurrenceID: item.occurrenceID, path: path)) }
            }
        }
        return Manifest(formatVersion: 1, occurrences: occurrences, missingMedia: missing)
    }

    static func json(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }
}
