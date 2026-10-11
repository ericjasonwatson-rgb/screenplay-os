import CryptoKit
import Darwin
import Foundation

/// Durable, new-destination publication for the native legacy conversion plans.
/// This remains separate from the active-document save path until parity tests pass.
enum NativeLegacyPackageWriter {
    enum Failure: Error, Equatable {
        case invalidDestination
        case destinationExists
        case changedSource
        case invalidPath(String)
        case readback
        case system(Int32)
    }

    struct RetainedFailure: Error {
        let phase: String
        let recoveryURL: URL
        let published: Bool
        let underlying: Error
    }

    struct Receipt: Equatable {
        let destination: URL
        let sourceSHA256: String
        let projectRevision: UUID
        let payloadFiles: Int
        let mediaAttachments: Int
    }

    static func write(
        preflight: NativeLegacyConversionPlan,
        identities: NativeLegacyIdentityPlan,
        payloadPlan: NativeLegacyPayloadPlan,
        destination: URL,
        checkpoint: (String, URL) throws -> Void = { _, _ in }
    ) throws -> Receipt {
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        guard target.pathExtension.lowercased() == "screenplay",
              parent.path != preflight.sourceURL.resolvingSymlinksInPath().path,
              !parent.path.hasPrefix(preflight.sourceURL.resolvingSymlinksInPath().path + "/")
        else { throw Failure.invalidDestination }
        guard !existsIncludingSymlink(target) else { throw Failure.destinationExists }
        guard try readRegular(preflight.sourceURL, limit: NativeLegacyConversionPlan.maximumSourceBytes) == preflight.sourceBytes
        else { throw Failure.changedSource }

        var files = payloadPlan.payloads
        files["project.json"] = payloadPlan.projectData
        files["provenance/source.json"] = preflight.sourceBytes
        files["provenance/candidate.json"] = try candidateData(preflight: preflight, identities: identities)
        try validatePaths(files.keys)

        let stage = parent.appendingPathComponent(".screenplay-conversion-" + UUID().uuidString + ".screenplay")
        guard mkdir(stage.path, 0o700) == 0 else { throw Failure.system(errno) }
        var phase = "staging_created"
        var published = false
        do {
            try checkpoint(phase, stage)
            for name in files.keys.sorted() {
                phase = "write:" + name
                let url = try makeParentDirectories(for: name, under: stage)
                try writeNew(url, data: files[name]!)
                try checkpoint(phase, stage)
            }
            try syncTree(stage)
            phase = "staged_readback"
            try checkpoint(phase, stage)
            guard try snapshot(stage) == files else { throw Failure.readback }
            _ = try PackagePreviewReader.read(stage)
            phase = "before_publish"
            try checkpoint(phase, stage)
            guard try readRegular(preflight.sourceURL, limit: NativeLegacyConversionPlan.maximumSourceBytes) == preflight.sourceBytes
            else { throw Failure.changedSource }
            guard renamex_np(stage.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw Failure.destinationExists }
                throw Failure.system(errno)
            }
            published = true
            phase = "published"
            try checkpoint(phase, target)
            try syncDirectory(parent)
            phase = "published_readback"
            try checkpoint(phase, target)
            guard try snapshot(target) == files else { throw Failure.readback }
            _ = try PackagePreviewReader.read(target)
            guard try readRegular(preflight.sourceURL, limit: NativeLegacyConversionPlan.maximumSourceBytes) == preflight.sourceBytes
            else { throw Failure.changedSource }
            return Receipt(destination: target, sourceSHA256: preflight.sourceSHA256,
                           projectRevision: identities.revisionID,
                           payloadFiles: payloadPlan.payloads.count,
                           mediaAttachments: preflight.attachments.count)
        } catch {
            throw RetainedFailure(phase: phase, recoveryURL: published ? target : stage,
                                  published: published, underlying: error)
        }
    }

    private static func candidateData(preflight: NativeLegacyConversionPlan,
                                      identities: NativeLegacyIdentityPlan) throws -> Data {
        let sceneMap = Dictionary(uniqueKeysWithValues: identities.sceneMap.map {
            ($0.key.uuidString.lowercased(), $0.value.uuidString.lowercased())
        })
        let references = identities.references.map {
            ["source_path": $0.sourcePath, "target_scene_id": $0.targetSceneID.uuidString.lowercased()]
        }
        return try JSONSerialization.data(withJSONObject: [
            "candidate_version": "0.1", "source_sha256": preflight.sourceSHA256,
            "scene_map": sceneMap, "reference_mapping": references,
            "conversion_ready": false,
            "limitations": [
                "The package is read-only in this build.",
                "Unknown, service, and production-lock data remains in the immutable legacy archive.",
                "Historical revision ancestry is not reconstructed."
            ]
        ], options: [.sortedKeys])
    }

    private static func validatePaths<S: Sequence>(_ paths: S) throws where S.Element == String {
        for path in paths {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty, !path.hasPrefix("/"), !path.hasSuffix("/"),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
            else { throw Failure.invalidPath(path) }
        }
    }

    private static func makeParentDirectories(for name: String, under root: URL) throws -> URL {
        let parts = name.split(separator: "/").map(String.init)
        var directory = root
        for part in parts.dropLast() {
            directory.appendPathComponent(part)
            if mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw Failure.system(errno) }
            var status = stat()
            guard lstat(directory.path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else {
                throw Failure.invalidPath(name)
            }
        }
        return directory.appendingPathComponent(parts.last!)
    }

    private static func snapshot(_ root: URL) throws -> [String: Data] {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = root.withUnsafeFileSystemRepresentation { path in
            path.flatMap { realpath($0, &buffer) }
        }
        guard resolved != nil else { throw Failure.system(errno) }
        let canonicalRoot = URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw Failure.readback }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw Failure.invalidPath("symlink:" + url.path) }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw Failure.invalidPath("nonregular:" + url.path) }
            guard url.path.hasPrefix(canonicalRoot.path + "/") else {
                throw Failure.invalidPath("outside:\(canonicalRoot.path):\(url.path)")
            }
            let name = String(url.path.dropFirst(canonicalRoot.path.count + 1))
            result[name] = try readRegular(url, limit: NativeLegacyConversionPlan.maximumImageBytes)
        }
        return result
    }

    private static func readRegular(_ url: URL, limit: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw Failure.system(errno) }
        guard status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0, status.st_size <= limit else {
            throw Failure.readback
        }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw Failure.system(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= limit else { throw Failure.readback }
        }
        guard data.count == status.st_size else { throw Failure.readback }
        return data
    }

    private static func writeNew(_ url: URL, data: Data) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        defer { close(descriptor) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw Failure.system(errno) }
                guard count > 0 else { throw Failure.system(EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 else { throw Failure.system(errno) }
    }

    private static func syncTree(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw Failure.readback
        }
        var directories = [root]
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            directories.append(url)
        }
        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) { try syncDirectory(directory) }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure.system(errno) }
    }

    private static func existsIncludingSymlink(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0
    }
}
