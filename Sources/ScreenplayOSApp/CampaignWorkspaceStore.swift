import Foundation
import Darwin
import ScreenplayDomain

/// Local companion storage, deliberately outside screenplay exports. No network,
/// private working-budget fields, or execution authority lives in this record.
enum CampaignWorkspaceStore {
    static let maximumBytes = 16 * 1_024 * 1_024
    struct Loaded {
        let ledger: CampaignLedger
        let bytes: Data?
    }
    enum Failure: LocalizedError {
        case unsafePath, unreadable, conflict, writeFailed, unsupportedData, wrongProject
        var errorDescription: String? {
            switch self {
            case .unsafePath: return "The campaign storage path is unsafe. No campaign data was changed."
            case .unreadable: return "The saved campaign could not be read. It has been left untouched."
            case .conflict: return "The campaign changed in another window or application. Close and reopen Campaign to reload it; this change was not saved."
            case .writeFailed: return "The campaign could not be saved. The last saved state is still active."
            case .unsupportedData: return "This campaign contains unsupported data. It has been left untouched."
            case .wrongProject: return "This campaign belongs to a different project. No data was changed."
            }
        }
    }

    static func url(projectID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScreenplayOS", isDirectory: true)
        return try canonicalRoot(base).appendingPathComponent("Campaigns", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("campaign-v1.json")
    }

    /// Resolve only the trusted storage root, never an existing campaign hierarchy.
    /// Foundation's resolvingSymlinksInPath can reintroduce /var after resolving it;
    /// POSIX realpath retains the literal /private/var path needed by lstat checks.
    static func canonicalRoot(_ root: URL) throws -> URL {
        guard root.isFileURL else { throw Failure.unsafePath }
        var existing = root
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            suffix.insert(existing.lastPathComponent, at: 0)
            let parent = existing.deletingLastPathComponent()
            guard parent.path != existing.path else { throw Failure.unsafePath }
            existing = parent
        }
        guard let resolved = realpath(existing.path, nil) else { throw Failure.unsafePath }
        defer { free(resolved) }
        var result = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        for component in suffix { result.appendPathComponent(component, isDirectory: true) }
        return result
    }

    static func load(projectID: UUID, from url: URL) throws -> Loaded {
        try validatePath(url)
        guard let bytes = try readBytes(url) else {
            return Loaded(ledger: CampaignLedger(projectID: projectID), bytes: nil)
        }
        return Loaded(ledger: try decode(bytes, projectID: projectID), bytes: bytes)
    }

    static func encoded(_ ledger: CampaignLedger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(ledger.validated())
        guard bytes.count <= maximumBytes else { throw Failure.unsupportedData }
        return bytes
    }

    static func decode(_ bytes: Data, projectID: UUID) throws -> CampaignLedger {
        guard bytes.count <= maximumBytes else { throw Failure.unsupportedData }
        _ = try PreservedJSON(bytes) // Reject duplicate keys before Codable can hide them.
        let ledger = try JSONDecoder().decode(CampaignLedger.self, from: bytes).validated()
        guard ledger.projectID == projectID else { throw Failure.wrongProject }
        // Fail closed rather than silently dropping future optional fields.
        let original = try JSONSerialization.jsonObject(with: bytes) as? NSDictionary
        let projected = try JSONSerialization.jsonObject(with: encoded(ledger)) as? NSDictionary
        guard let original, let projected, original.isEqual(projected) else {
            throw Failure.unsupportedData
        }
        return ledger
    }

    /// Cooperating writers use a file lock plus an exact-byte lease. Noncooperating
    /// writers can still race after the check; this is not cross-device sync.
    @discardableResult
    static func save(_ ledger: CampaignLedger, to url: URL, expected: Data?) throws -> Data {
        let bytes = try encoded(ledger)
        try validatePath(url)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try validatePath(url)
        let lockURL = parent.appendingPathComponent(".campaign.lock")
        let lock = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure.unsafePath }
        defer { flock(lock, LOCK_UN); close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              flock(lock, LOCK_EX) == 0 else { throw Failure.unsafePath }
        try validatePath(url)
        let current = try readBytes(url)
        guard current == expected else { throw Failure.conflict }
        if let current { _ = try decode(current, projectID: ledger.projectID) }
        let stage = parent.appendingPathComponent(".campaign-\(UUID().uuidString).tmp")
        let fd = open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.writeFailed }
        defer { close(fd); try? FileManager.default.removeItem(at: stage) }
        let succeeded = bytes.withUnsafeBytes { buffer -> Bool in
            guard let address = buffer.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, address.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return fsync(fd) == 0
        }
        guard succeeded, try readBytes(stage) == bytes else { throw Failure.writeFailed }
        guard rename(stage.path, url.path) == 0 else { throw Failure.writeFailed }
        // A successful atomic replacement is the commit boundary. Do not report
        // failure afterwards, which could make callers retry a committed action.
        let directory = open(parent.path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); close(directory) }
        return bytes
    }

    private static func readBytes(_ url: URL) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw Failure.unreadable
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= Int64(maximumBytes) else { throw Failure.unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let bytes = try handle.readToEnd() ?? Data()
        guard bytes.count <= maximumBytes else { throw Failure.unreadable }
        return bytes
    }

    private static func validatePath(_ url: URL) throws {
        guard url.isFileURL else { throw Failure.unsafePath }
        // /tmp and /var are system aliases on macOS. Resolve those once at the
        // caller's root; never follow a symlink within the campaign hierarchy.
        // Do not use standardizedFileURL here: Foundation can shorten the resolved
        // /private/var path back to the /var symlink on macOS. Walk literal paths.
        let path = url.path
        guard path.hasPrefix("/"), !url.pathComponents.contains(".."),
              !url.pathComponents.contains(".") else { throw Failure.unsafePath }
        var current = path
        while current != "/" {
            var info = stat()
            if lstat(current, &info) == 0 {
                guard (info.st_mode & S_IFMT) != S_IFLNK else { throw Failure.unsafePath }
                if current != path {
                    guard (info.st_mode & S_IFMT) == S_IFDIR else { throw Failure.unsafePath }
                }
            } else if errno != ENOENT { throw Failure.unsafePath }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current, !parent.isEmpty else { throw Failure.unsafePath }
            current = parent
        }
    }
}
