import Darwin
import Foundation
import ScreenplayDomain

enum PackageRecovery {
    struct Record: Codable, Identifiable {
        let version: Int
        let id: UUID
        let title: String
        let originalSource: URL
        let savedAt: Date
        let selected: UUID?
        let files: [String: Data]
    }
    static func write(_ record: Record, directory: URL, beforePublish: () throws -> Void = {}) throws {
        _ = try PackageTextSession(files: record.files)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = directory.appendingPathComponent(record.id.uuidString + ".json")
        let stage = directory.appendingPathComponent(".pending-" + UUID().uuidString)
        let data = try JSONEncoder().encode(record)
        let fd = open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw POSIXError(.EIO) }
        try beforePublish()
        guard rename(stage.path, target.path) == 0 else { throw POSIXError(.EIO) }
        try sync(directory)
    }
    static func read(_ url: URL) throws -> Record {
        let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard attributes.isSymbolicLink != true, attributes.isRegularFile == true,
              (attributes.fileSize ?? Int.max) <= 100 * 1024 * 1024 else { throw POSIXError(.EINVAL) }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard record.version == 1, url.deletingPathExtension().lastPathComponent == record.id.uuidString else { throw POSIXError(.EINVAL) }
        _ = try PackageTextSession(files: record.files)
        return record
    }
    static func list(_ directory: URL) -> [Record] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.compactMap { try? read($0) }.sorted { $0.savedAt > $1.savedAt }
    }
    static func remove(_ id: UUID, directory: URL) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            try sync(directory)
        }
    }
    static func materialize(_ record: Record, directory: URL) throws -> URL {
        _ = try PackageTextSession(files: record.files)
        let target = directory.appendingPathComponent("Recovered-" + UUID().uuidString + ".screenplay")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, data) in record.files {
            let url = target.appendingPathComponent(name)
            try data.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        _ = try PackageEditedCopy.load(target)
        return target
    }
    private static func sync(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }
}
