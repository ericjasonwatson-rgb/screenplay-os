import Foundation

public enum EditAudioLane: String, Codable, CaseIterable, Sendable {
    case dialogue, music, effects
}

public struct EditAudioClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var lane: EditAudioLane
    public var name: String
    public var mediaURL: URL
    public var sha256: String
    public var timelineStartSeconds: Double
    public var sourceInSeconds: Double
    public var durationSeconds: Double

    public init(
        id: UUID = UUID(), lane: EditAudioLane, name: String, mediaURL: URL, sha256: String,
        timelineStartSeconds: Double, sourceInSeconds: Double = 0, durationSeconds: Double
    ) {
        self.id = id; self.lane = lane; self.name = name; self.mediaURL = mediaURL; self.sha256 = sha256
        self.timelineStartSeconds = timelineStartSeconds; self.sourceInSeconds = sourceInSeconds
        self.durationSeconds = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, lane, name, sha256
        case mediaURL = "media_url"
        case timelineStartSeconds = "timeline_start_seconds"
        case sourceInSeconds = "source_in_seconds"
        case durationSeconds = "duration_seconds"
    }
}

public struct ActiveAudioSlice: Equatable, Sendable {
    public let clip: EditAudioClip
    public let sourceOffsetSeconds: Double
    public let remainingSeconds: Double
}

public struct EditAudioLedger: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let projectID: UUID
    public var clips: [EditAudioClip]

    public init(version: Int = EditAudioLedger.currentVersion, projectID: UUID, clips: [EditAudioClip] = []) {
        self.version = version; self.projectID = projectID; self.clips = clips
    }

    enum CodingKeys: String, CodingKey {
        case version, clips
        case projectID = "project_id"
    }

    public func validated() throws -> EditAudioLedger {
        guard version == Self.currentVersion else { throw EditAudioError.unsupportedVersion }
        guard Set(clips.map(\.id)).count == clips.count else { throw EditAudioError.duplicateClip }
        for clip in clips {
            guard !clip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  clip.name.utf8.count <= 1_000,
                  clip.mediaURL.isFileURL, !clip.mediaURL.path.isEmpty,
                  clip.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw EditAudioError.invalidMedia
            }
            guard clip.timelineStartSeconds.isFinite, clip.timelineStartSeconds >= 0,
                  clip.sourceInSeconds.isFinite, clip.sourceInSeconds >= 0,
                  clip.durationSeconds.isFinite, clip.durationSeconds > 0,
                  clip.timelineStartSeconds + clip.durationSeconds < 86_400 else {
                throw EditAudioError.invalidTiming
            }
        }
        return self
    }

    public func activeSlices(at playhead: Double) -> [ActiveAudioSlice] {
        guard playhead.isFinite, playhead >= 0 else { return [] }
        return clips.compactMap { clip in
            let elapsed = playhead - clip.timelineStartSeconds
            guard elapsed >= 0, elapsed < clip.durationSeconds else { return nil }
            return ActiveAudioSlice(
                clip: clip,
                sourceOffsetSeconds: clip.sourceInSeconds + elapsed,
                remainingSeconds: clip.durationSeconds - elapsed
            )
        }.sorted { ($0.clip.lane.rawValue, $0.clip.timelineStartSeconds, $0.clip.id.uuidString) <
            ($1.clip.lane.rawValue, $1.clip.timelineStartSeconds, $1.clip.id.uuidString) }
    }
}

public enum EditAudioError: Error, Equatable {
    case unsupportedVersion, duplicateClip, projectMismatch, invalidMedia, invalidTiming, clipNotFound, invalidFile
}

public enum EditAudioFileStore {
    public static let maximumBytes = 20 * 1_024 * 1_024

    public static func write(_ ledger: EditAudioLedger, to url: URL) throws {
        guard url.isFileURL else { throw EditAudioError.invalidFile }
        try validateDestination(url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(ledger.validated())
        guard data.count <= maximumBytes else { throw EditAudioError.invalidFile }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL) throws -> EditAudioLedger {
        guard url.isFileURL else { throw EditAudioError.invalidFile }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else { throw EditAudioError.invalidFile }
        return try JSONDecoder().decode(EditAudioLedger.self, from: Data(contentsOf: url)).validated()
    }

    private static func validateDestination(_ url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EditAudioError.invalidFile }
        }
        var parent = url.deletingLastPathComponent()
        while !manager.fileExists(atPath: parent.path) {
            let next = parent.deletingLastPathComponent()
            guard next.path != parent.path else { throw EditAudioError.invalidFile }
            parent = next
        }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw EditAudioError.invalidFile }
    }
}

public actor EditAudioController {
    public let projectID: UUID
    public let storageURL: URL
    private var ledger: EditAudioLedger

    public init(projectID: UUID, storageURL: URL) throws {
        self.projectID = projectID; self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let loaded = try EditAudioFileStore.read(from: storageURL)
            guard loaded.projectID == projectID else { throw EditAudioError.projectMismatch }
            ledger = loaded
        } else {
            ledger = EditAudioLedger(projectID: projectID)
        }
    }

    public func snapshot() -> EditAudioLedger { ledger }

    public func add(_ clip: EditAudioClip) throws {
        var candidate = ledger
        candidate.clips.append(clip)
        try commit(candidate)
    }

    public func remove(_ id: UUID) throws {
        guard ledger.clips.contains(where: { $0.id == id }) else { throw EditAudioError.clipNotFound }
        var candidate = ledger
        candidate.clips.removeAll { $0.id == id }
        try commit(candidate)
    }

    private func commit(_ candidate: EditAudioLedger) throws {
        let validated = try candidate.validated()
        try EditAudioFileStore.write(validated, to: storageURL)
        ledger = validated
    }
}
