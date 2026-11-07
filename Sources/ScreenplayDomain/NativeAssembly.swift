import CryptoKit
import Foundation

/// First-party, image-only assembly model. It does not depend on FilmCraft's
/// native project format or mutate the screenplay/board source of truth.
public struct NativeAssemblyClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID                 // Timeline occurrence, never the Take identity.
    public var sceneSpineID: String
    public var shotID: UUID
    public var boardFrameID: UUID
    public var takeID: UUID
    public var generationJobID: UUID?
    public var mediaSHA256: String
    public var promptSHA256: String?
    public var mediaPath: String        // Portable, Board Images/<basename> only.
    public var label: String
    public var frameCount: Int

    public init(id: UUID = UUID(), sceneSpineID: String, shotID: UUID, boardFrameID: UUID,
                takeID: UUID, generationJobID: UUID? = nil, mediaSHA256: String,
                promptSHA256: String? = nil, mediaPath: String, label: String,
                frameCount: Int) {
        self.id = id
        self.sceneSpineID = sceneSpineID
        self.shotID = shotID
        self.boardFrameID = boardFrameID
        self.takeID = takeID
        self.generationJobID = generationJobID
        self.mediaSHA256 = mediaSHA256
        self.promptSHA256 = promptSHA256
        self.mediaPath = mediaPath
        self.label = label
        self.frameCount = frameCount
    }
}

public enum NativeAssemblyError: Error, Equatable {
    case unsupportedVersion, wrongProject, invalidClip, duplicateOccurrence
    case emptySelection, unknownClip, invalidEdit, staleBoards, invalidFile
}

/// Exactly 24 integer frames per second. The schema is deliberately independent
/// of the screenplay package, and is never treated as authoritative source data.
public struct NativeAssemblyProject: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let framesPerSecond = 24
    public static let maximumFrames = 24 * 60 * 30
    public var version: Int
    public var projectID: UUID
    public var sceneSpineID: String
    public var boardRevision: String
    public var clips: [NativeAssemblyClip]

    public init(projectID: UUID, sceneSpineID: String, boardRevision: String,
                clips: [NativeAssemblyClip], version: Int = currentVersion) {
        self.version = version
        self.projectID = projectID
        self.sceneSpineID = sceneSpineID
        self.boardRevision = boardRevision
        self.clips = clips
    }

    public var totalFrames: Int { clips.reduce(0) { $0 + $1.frameCount } }

    public func validated() throws -> NativeAssemblyProject {
        guard version == Self.currentVersion, !sceneSpineID.isEmpty,
              sceneSpineID.utf8.count <= 256 else { throw NativeAssemblyError.unsupportedVersion }
        guard Self.digest(boardRevision), clips.count <= 5_000,
              Set(clips.map(\.id)).count == clips.count else {
            throw NativeAssemblyError.duplicateOccurrence
        }
        var frames = 0
        for clip in clips {
            guard clip.sceneSpineID == sceneSpineID, clip.frameCount > 0,
                  clip.frameCount <= Self.maximumFrames,
                  frames <= Self.maximumFrames - clip.frameCount,
                  clip.label.utf8.count <= 500,
                  Self.digest(clip.mediaSHA256),
                  clip.promptSHA256.map(Self.digest) ?? true,
                  Self.safeMediaPath(clip.mediaPath) else { throw NativeAssemblyError.invalidClip }
            frames += clip.frameCount
        }
        return self
    }

    public func isCurrent(with boards: [BoardFrame]) -> Bool {
        (try? BoardTakeMigration.sourceRevision(boards)) == boardRevision
    }

    public func clip(at frame: Int) -> NativeAssemblyClip? {
        guard frame >= 0 else { return nil }
        var cursor = 0
        for clip in clips {
            if frame < cursor + clip.frameCount { return clip }
            cursor += clip.frameCount
        }
        return nil
    }

    /// Only selected image versions become assembled clips. Nothing is generated,
    /// imported from a provider, relinked or adopted into the original screenplay.
    public static func assemble(projectID: UUID, sceneSpineID: String,
                                boards: [BoardFrame]) throws -> NativeAssemblyProject {
        guard !sceneSpineID.isEmpty else { throw NativeAssemblyError.invalidClip }
        let selectedBoards = boards.filter { $0.sceneSpineID == sceneSpineID }
            .sorted { ($0.frameNumber, $0.id.uuidString) < ($1.frameNumber, $1.id.uuidString) }
        let revision = try BoardTakeMigration.sourceRevision(selectedBoards)
        var items: [NativeAssemblyClip] = []
        for board in selectedBoards {
            guard let image = board.selectedImage else { continue }
            guard board.durationSeconds.isFinite, board.durationSeconds > 0,
                  board.durationSeconds <= 3600 else { throw NativeAssemblyError.invalidClip }
            let frameCount = Int((board.durationSeconds * Double(framesPerSecond)).rounded())
            let mediaPath = try Self.portablePath(image.fileURL)
            let promptDigest: String? = image.generationJobID.map { _ in
                SHA256.hash(data: Data(image.prompt.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            items.append(NativeAssemblyClip(
                sceneSpineID: sceneSpineID, shotID: board.shotID, boardFrameID: board.id,
                takeID: image.id, generationJobID: image.generationJobID,
                mediaSHA256: image.sha256, promptSHA256: promptDigest,
                mediaPath: mediaPath, label: board.label, frameCount: frameCount
            ))
        }
        guard !items.isEmpty else { throw NativeAssemblyError.emptySelection }
        return try NativeAssemblyProject(projectID: projectID, sceneSpineID: sceneSpineID,
                                         boardRevision: revision, clips: items).validated()
    }

    /// A split creates a NEW occurrence while preserving the underlying Take.
    /// The original occurrence retains its ID on the left side.
    public func splitting(_ id: UUID, afterFrames: Int,
                          newOccurrenceID: UUID = UUID()) throws -> NativeAssemblyProject {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { throw NativeAssemblyError.unknownClip }
        guard afterFrames > 0, afterFrames < clips[index].frameCount,
              !clips.contains(where: { $0.id == newOccurrenceID }) else { throw NativeAssemblyError.invalidEdit }
        var result = self
        var right = result.clips[index]
        right.id = newOccurrenceID
        right.frameCount -= afterFrames
        result.clips[index].frameCount = afterFrames
        result.clips.insert(right, at: index + 1)
        return try result.validated()
    }

    public func trimming(_ id: UUID, toFrames newCount: Int) throws -> NativeAssemblyProject {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { throw NativeAssemblyError.unknownClip }
        guard newCount > 0, newCount <= Self.maximumFrames else { throw NativeAssemblyError.invalidEdit }
        var result = self
        result.clips[index].frameCount = newCount
        return try result.validated()
    }

    public func moving(_ id: UUID, by offset: Int) throws -> NativeAssemblyProject {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { throw NativeAssemblyError.unknownClip }
        let destination = index + offset
        guard clips.indices.contains(destination) else { throw NativeAssemblyError.invalidEdit }
        var result = self
        let clip = result.clips.remove(at: index)
        result.clips.insert(clip, at: destination)
        return try result.validated()
    }

    public func duplicating(_ id: UUID, newOccurrenceID: UUID = UUID()) throws -> NativeAssemblyProject {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { throw NativeAssemblyError.unknownClip }
        guard !clips.contains(where: { $0.id == newOccurrenceID }) else { throw NativeAssemblyError.invalidEdit }
        var result = self
        var duplicate = result.clips[index]
        duplicate.id = newOccurrenceID
        result.clips.insert(duplicate, at: index + 1)
        return try result.validated()
    }

    public static func digest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    public static func safeMediaPath(_ value: String) -> Bool {
        guard value.utf8.count <= 512, value.hasPrefix("Board Images/") else { return false }
        let name = String(value.dropFirst("Board Images/".count))
        return !name.isEmpty && name != "." && name != ".." &&
            !name.contains("/") && !name.contains("\\") &&
            !name.contains(":") && !name.contains("%") &&
            name.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }

    private static func portablePath(_ url: URL) throws -> String {
        let path: String
        if url.isFileURL {
            guard url.deletingLastPathComponent().lastPathComponent == "Board Images" else {
                throw NativeAssemblyError.invalidClip
            }
            path = "Board Images/" + url.lastPathComponent
        } else {
            guard url.scheme == nil, url.host == nil, url.query == nil, url.fragment == nil else {
                throw NativeAssemblyError.invalidClip
            }
            path = url.path
        }
        guard safeMediaPath(path) else { throw NativeAssemblyError.invalidClip }
        return path
    }
}

/// A separate project-bound local sidecar. No network use and no change to
/// screenplay source, existing Take ledger, or FilmCraft's .fcproj format.
public enum NativeAssemblyFileStore {
    public static let maximumBytes = 5 * 1_024 * 1_024

    public static func url(projectID: UUID, sceneSpineID: String, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let sceneHash = SHA256.hash(data: Data(sceneSpineID.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("ScreenplayOS/NativeAssemblies/\(projectID.uuidString)/\(sceneHash).json")
    }

    public static func save(_ project: NativeAssemblyProject, to url: URL) throws {
        guard url.isFileURL else { throw NativeAssemblyError.invalidFile }
        _ = try project.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(project)
        guard data.count <= maximumBytes else { throw NativeAssemblyError.invalidFile }
        let manager = FileManager.default
        // Do not follow an attacker-controlled sidecar directory symlink.
        var existingParent = url.deletingLastPathComponent()
        while !manager.fileExists(atPath: existingParent.path) {
            let next = existingParent.deletingLastPathComponent()
            guard next.path != existingParent.path else { throw NativeAssemblyError.invalidFile }
            existingParent = next
        }
        let parent = try existingParent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parent.isDirectory == true, parent.isSymbolicLink != true else {
            throw NativeAssemblyError.invalidFile
        }
        if manager.fileExists(atPath: url.path) {
            let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard value.isRegularFile == true, value.isSymbolicLink != true else {
                throw NativeAssemblyError.invalidFile
            }
        }
        try manager.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL ==
              url.deletingLastPathComponent().standardizedFileURL else {
            throw NativeAssemblyError.invalidFile
        }
        try data.write(to: url, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func load(from url: URL, projectID: UUID, sceneSpineID: String) throws -> NativeAssemblyProject {
        guard url.isFileURL else { throw NativeAssemblyError.invalidFile }
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true,
              let size = value.fileSize, size <= maximumBytes else { throw NativeAssemblyError.invalidFile }
        let project = try JSONDecoder().decode(NativeAssemblyProject.self, from: Data(contentsOf: url)).validated()
        guard project.projectID == projectID, project.sceneSpineID == sceneSpineID else {
            throw NativeAssemblyError.wrongProject
        }
        return project
    }
}
