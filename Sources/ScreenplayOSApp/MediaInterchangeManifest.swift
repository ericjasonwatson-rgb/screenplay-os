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



    /// Resolve a packaged media path without allowing symlinks to escape the package.
    /// This does not copy, decode, upload, or modify the media.
    static func containedMediaURL(_ path: String, projectRoot: URL) throws -> URL {
        guard safeRelativePath(path) else { throw ValidationError.unsafePath }
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix) else { throw ValidationError.unsafePath }
        return candidate
    }

    /// Check references on disk without inventing links to absent assets.
    /// The project root must be a trusted local directory selected by the caller.
    static func make(_ occurrences: [Occurrence], projectRoot: URL) throws -> Manifest {
        // Validate all paths, including paths for missing files, before testing existence.
        for item in occurrences {
            if let path = item.mediaPath {
                _ = try containedMediaURL(path, projectRoot: projectRoot)
            }
        }
        return try make(occurrences) { path in
            guard let url = try? containedMediaURL(path, projectRoot: projectRoot) else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    /// Explicit binding from a derived timeline segment to canonical objects.
    /// Never infer scene or shot identity from a display label.
    struct SourceBinding {
        let sceneID: UUID
        let shotID: UUID
        let boardID: UUID?
        let mediaPath: String?
        let note: String
    }

    enum TimelineError: Error, Equatable {
        case missingBinding(UUID)
        case duplicateSegment(UUID)
        case invalidFrameTiming
    }

    /// Converts existing timed edit segments to a read-only manifest.
    /// The caller must provide a canonical identity binding for every segment.
    /// No identity is fabricated and no canonical project data is mutated.
    static func fromTimeline(
        _ segments: [TimedEditSegment],
        bindings: [UUID: SourceBinding],
        mediaExists: (String) -> Bool
    ) throws -> Manifest {
        var seen = Set<UUID>()
        var occurrences: [Occurrence] = []
        for segment in segments {
            guard seen.insert(segment.id).inserted else { throw TimelineError.duplicateSegment(segment.id) }
            guard let binding = bindings[segment.id] else { throw TimelineError.missingBinding(segment.id) }
            guard segment.start.isFinite, segment.duration.isFinite,
                  segment.start >= 0, segment.duration > 0,
                  segment.start <= Double(Int.max / 24),
                  segment.duration <= Double(Int.max / 24) else {
                throw TimelineError.invalidFrameTiming
            }
            let start = (segment.start * 24).rounded()
            let duration = (segment.duration * 24).rounded()
            guard start >= 0, duration >= 1, start <= Double(Int.max / 2),
                  duration <= Double(Int.max / 2) else { throw TimelineError.invalidFrameTiming }
            occurrences.append(Occurrence(
                occurrenceID: segment.id, sceneID: binding.sceneID, shotID: binding.shotID,
                boardID: binding.boardID, mediaPath: binding.mediaPath,
                startFrame: Int(start), durationFrames: Int(duration), note: binding.note
            ))
        }
        return try make(occurrences, mediaExists: mediaExists)
    }


    enum ImportError: Error, Equatable {
        case unsupportedVersion
        case invalidMissingMediaReport
    }

    /// Validates an interchange snapshot without modifying project data.
    /// This is not an editorial round-trip importer.
    static func read(_ data: Data) throws -> Manifest {
        let decoded = try JSONDecoder().decode(Manifest.self, from: data)
        guard decoded.formatVersion == 1 else { throw ImportError.unsupportedVersion }
        let verified = try make(decoded.occurrences, mediaExists: { _ in true })
        let known = Dictionary(uniqueKeysWithValues:
            verified.occurrences.map { ($0.occurrenceID, $0.mediaPath) })
        var reported = Set<UUID>()
        for item in decoded.missingMedia {
            guard reported.insert(item.occurrenceID).inserted,
                  known[item.occurrenceID] == item.path else {
                throw ImportError.invalidMissingMediaReport
            }
        }
        return decoded
    }

    static func json(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }
}
