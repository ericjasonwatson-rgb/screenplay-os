import AVFoundation
import CryptoKit
import Foundation
import ScreenplayDomain

/// Explicit, local import of an MOV/MP4 as an assembly-only Take. The
/// authoritative ScreenplayOS Take ledger is never silently modified.
enum NativeVideoTakeImporter {
    enum Failure: LocalizedError {
        case unsavedProject, unsafeSource, unsupportedFormat, invalidVideo
        case mediaTooLarge, mediaChanged, unsafeDestination

        var errorDescription: String? {
            switch self {
            case .unsavedProject: return "Save the screenplay before importing a local video Take."
            case .unsafeSource: return "Video import requires an ordinary local MOV or MP4 file."
            case .unsupportedFormat: return "Only .mov and .mp4 files are supported in this preview."
            case .invalidVideo: return "The selected media has no usable video track or valid duration."
            case .mediaTooLarge: return "This preview limits video Takes to 512 MB and 30 minutes."
            case .mediaChanged: return "The imported video changed during copying."
            case .unsafeDestination: return "The project Video Takes directory is not safe to use."
            }
        }
    }

    static let maximumBytes = 512 * 1_024 * 1_024

    /// The chosen source must come from an explicit user file panel.
    /// The imported copy is portable with the screenplay's media folder.
    static func importLocalVideo(_ source: URL, screenplayURL: URL,
                                 after parent: NativeAssemblyClip) async throws -> NativeAssemblyClip {
        guard screenplayURL.isFileURL else { throw Failure.unsavedProject }
        guard source.isFileURL else { throw Failure.unsafeSource }
        let ext = source.pathExtension.lowercased()
        guard ext == "mov" || ext == "mp4" else { throw Failure.unsupportedFormat }
        let sourceInfo = try source.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard sourceInfo.isRegularFile == true, sourceInfo.isSymbolicLink != true else {
            throw Failure.unsafeSource
        }
        guard let size = sourceInfo.fileSize, size > 0, size <= maximumBytes else {
            throw Failure.mediaTooLarge
        }

        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        guard !tracks.isEmpty, duration.isNumeric, duration.seconds.isFinite,
              duration.seconds >= 1.0 / 24.0, duration.seconds <= 1800 else {
            throw Failure.invalidVideo
        }
        let sourceFrames = Int((duration.seconds * 24.0).rounded(.down))
        guard sourceFrames > 0, sourceFrames <= NativeAssemblyProject.maximumFrames else {
            throw Failure.invalidVideo
        }
        let sourceDigest = try digest(source)

        let folder = screenplayURL.deletingLastPathComponent()
            .appendingPathComponent("Video Takes", isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else {
                throw Failure.unsafeDestination
            }
        } else {
            try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
        }
        let filename = sourceDigest + "." + ext
        let destination = folder.appendingPathComponent(filename)
        let staging = folder.appendingPathComponent("." + UUID().uuidString + ".part")
        defer { try? manager.removeItem(at: staging) }

        if manager.fileExists(atPath: destination.path) {
            try verify(destination, digest: sourceDigest)
        } else {
            // Stage in the same folder before publishing; no source file is moved.
            try manager.copyItem(at: source, to: staging)
            try verify(staging, digest: sourceDigest)
            do {
                try manager.moveItem(at: staging, to: destination)
            } catch {
                // Another importer could have published identical content.
                guard manager.fileExists(atPath: destination.path) else { throw error }
                try verify(destination, digest: sourceDigest)
            }
        }

        // Imported creative media is private to the local user by default.
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        // A local, assembly-owned video Take gets a new source Take ID.
        // Only its occurrence gets a new occurrence ID after insertion.
        return NativeAssemblyClip(
            sceneSpineID: parent.sceneSpineID, shotID: parent.shotID,
            boardFrameID: parent.boardFrameID, takeID: UUID(),
            mediaSHA256: sourceDigest, mediaPath: "Video Takes/" + filename,
            label: source.deletingPathExtension().lastPathComponent,
            frameCount: sourceFrames, mediaKind: .video,
            sourceInFrame: 0, sourceFrameLimit: sourceFrames)
    }

    static func verify(_ file: URL, digest expected: String) throws {
        let info = try file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size > 0, size <= maximumBytes else {
            throw Failure.unsafeDestination
        }
        guard try digest(file) == expected else { throw Failure.mediaChanged }
    }

    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
