import CryptoKit
import Darwin
import Foundation
import ScreenplayDomain

/// macOS new-copy persistence for the minimal, two-file editing profile.
/// Never use this to overwrite a package or to discard unsupported companions.
enum PackageEditedCopy {
    enum Failure: Error { case unsupported, changedSource, readback, system(Int32) }
    struct RetainedFailure: Error {
        let phase: String
        let recoveryURL: URL
        let published: Bool
        let underlying: Error
    }
    struct Receipt {
        let destination: URL
        let sessionRevision: UUID
        let sha256: [String: String]
    }

    static func load(_ source: URL) throws -> PackageTextSession {
        let files = try snapshot(source)
        let result = try PackageTextSession(files: files)
        guard try snapshot(source) == files else { throw Failure.changedSource }
        return result
    }

    static func save(_ session: PackageTextSession, source: URL, destination: URL,
                     now: Date = Date(), checkpoint: (String, URL) throws -> Void = { _, _ in }) throws -> Receipt {
        guard destination.pathExtension == "screenplay" else { throw Failure.unsupported }
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        let sourcePath = source.resolvingSymlinksInPath().path
        guard parent.path != sourcePath, !parent.path.hasPrefix(sourcePath + "/"),
              target.path != sourcePath else { throw Failure.unsupported }
        guard try snapshot(source) == session.originalFiles else { throw Failure.changedSource }
        // Only manifest modification time and explicitly edited text can change.
        var files = session.currentFiles
        var manifest = try PreservedJSON(files["manifest.json"]!)
        try manifest.replaceString(at: [.key("format")], expected: manifest.string(at: [.key("format")]),
                                   with: "screenplayos")
        let oldTime = try manifest.string(at: [.key("modified_at")])
        try manifest.replaceString(at: [.key("modified_at")], expected: oldTime,
                                   with: ISO8601DateFormatter().string(from: now))
        files["manifest.json"] = manifest.data
        files["screenplay.json"] = session.screenplayBytes
        _ = try PackageTextSession(files: files)
        let stage = parent.appendingPathComponent(".screenplay-edit-" + UUID().uuidString)
        guard mkdir(stage.path, 0o700) == 0 else { throw Failure.system(errno) }
        var phase = "staging_created", published = false
        do {
            try checkpoint(phase, stage)
            for name in files.keys.sorted() {
                phase = "write:" + name
                try writeNew(stage.appendingPathComponent(name), data: files[name]!)
                try checkpoint(phase, stage)
            }
            try syncDirectory(stage)
            phase = "staged_readback"
            try checkpoint(phase, stage)
            guard try snapshot(stage) == files else { throw Failure.readback }
            _ = try load(stage)
            phase = "before_publish"
            try checkpoint(phase, stage)
            guard try snapshot(source) == session.originalFiles else { throw Failure.changedSource }
            // RENAME_EXCL refuses an existing file, directory, or symlink atomically.
            guard renamex_np(stage.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure.system(errno) }
            published = true
            phase = "published"
            try checkpoint(phase, target)
            try syncDirectory(parent)
            phase = "published_readback"
            try checkpoint(phase, target)
            guard try snapshot(target) == files else { throw Failure.readback }
            _ = try load(target)
            guard try snapshot(source) == session.originalFiles else { throw Failure.changedSource }
            return Receipt(destination: target, sessionRevision: session.revision,
                           sha256: files.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() })
        } catch {
            // Leave complete or partial staging/output for recovery; never remove a competitor.
            throw RetainedFailure(phase: phase, recoveryURL: published ? target : stage,
                                  published: published, underlying: error)
        }
    }

    static func isFinderMetadata(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._") || name == "Icon\r"
    }

    static func snapshot(_ root: URL) throws -> [String: Data] {
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        defer { close(descriptor) }
        // Finder and non-APFS volumes add metadata files (.DS_Store, AppleDouble "._*",
        // custom-icon "Icon\r"). They are not authored content and must not block saving.
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !isFinderMetadata($0) }
        guard Set(names).isSubset(of: ["manifest.json", "screenplay.json", "settings.json"]), Set(names).isSuperset(of: ["manifest.json", "screenplay.json"]) else { throw Failure.unsupported }
        var result: [String: Data] = [:]
        for name in names {
            let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard file >= 0 else { throw Failure.system(errno) }
            defer { close(file) }
            var status = stat()
            guard fstat(file, &status) == 0 else { throw Failure.system(errno) }
            guard status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0,
                  status.st_size <= 32 * 1024 * 1024 else { throw Failure.unsupported }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = read(file, &buffer, buffer.count)
                if count < 0 { if errno == EINTR { continue }; throw Failure.system(errno) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
                guard data.count <= 32 * 1024 * 1024 else { throw Failure.unsupported }
            }
            guard data.count == status.st_size else { throw Failure.changedSource }
            result[name] = data
        }
        guard Set(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !isFinderMetadata($0) }) == Set(names) else { throw Failure.changedSource }
        return result
    }

    static func writeNew(_ url: URL, data: Data) throws {
        let file = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw Failure.system(errno) }
        defer { close(file) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw Failure.system(errno) }
                guard count > 0 else { throw Failure.system(EIO) }
                offset += count
            }
        }
        guard fsync(file) == 0, fcntl(file, F_FULLFSYNC) == 0 else { throw Failure.system(errno) }
    }
    static func syncDirectory(_ url: URL) throws {
        let file = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard file >= 0 else { throw Failure.system(errno) }
        defer { close(file) }
        guard fsync(file) == 0 else { throw Failure.system(errno) }
    }
}
