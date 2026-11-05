import CryptoKit
import Foundation

/// Stores a validated provider result before the job is marked successful.
/// The recovery asset is deliberately separate from Board selection and can
/// be used to finish local adoption without paying for a second generation.
enum ProductionImageResultVault {
    enum Failure: Error, Equatable {
        case invalidAsset
        case unsafeStorage
        case conflictingResult
        case missingResult
    }

    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private static func destination(
        projectID: UUID, jobID: UUID, root: URL
    ) throws -> URL {
        guard root.isFileURL else { throw Failure.unsafeStorage }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        guard base.isFileURL else { throw Failure.unsafeStorage }
        let manager = FileManager.default
        let folders = ["ScreenplayOS", "Production Image Results", projectID.uuidString]
        var folder = base
        for name in folders {
            folder.appendPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: folder.path) {
                let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true && info.isSymbolicLink != true else {
                    throw Failure.unsafeStorage
                }
            }
        }
        return folder.appendingPathComponent(jobID.uuidString + ".png")
    }

    @discardableResult
    static func store(
        _ png: Data, projectID: UUID, jobID: UUID, root: URL
    ) throws -> URL {
        guard BoardImageAPI.validPNG(png) else { throw Failure.invalidAsset }
        let url = try destination(projectID: projectID, jobID: jobID, root: root)
        let manager = FileManager.default
        var path = root.resolvingSymlinksInPath().standardizedFileURL
        for segment in ["ScreenplayOS", "Production Image Results", projectID.uuidString] {
            path.appendPathComponent(segment, isDirectory: true)
            if !manager.fileExists(atPath: path.path) {
                try manager.createDirectory(at: path, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
            }
            let info = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true && info.isSymbolicLink != true else {
                throw Failure.unsafeStorage
            }
        }
        if manager.fileExists(atPath: url.path) ||
            url.resolvingSymlinksInPath().standardizedFileURL != url.standardizedFileURL {
            guard (try? load(projectID: projectID, jobID: jobID, root: root)) == png else {
                throw Failure.conflictingResult
            }
            return url
        }
        // An exclusive write prevents silently replacing a different paid result
        // associated with this generation job.
        try png.write(to: url, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func load(
        projectID: UUID, jobID: UUID, root: URL
    ) throws -> Data {
        let url = try destination(projectID: projectID, jobID: jobID, root: root)
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL,
              let info = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size > 0, size <= 20_000_000,
              let bytes = try? Data(contentsOf: url), bytes.count == size,
              BoardImageAPI.validPNG(bytes)
        else { throw Failure.missingResult }
        return bytes
    }

    /// Reconstruct the strict single-image response for the existing verified
    /// candidate preparation path; no provider or network access occurs.
    static func recoverResponse(
        projectID: UUID, jobID: UUID, root: URL
    ) throws -> Data {
        let bytes = try load(projectID: projectID, jobID: jobID, root: root)
        return try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": bytes.base64EncodedString()]]
        ])
    }
}
