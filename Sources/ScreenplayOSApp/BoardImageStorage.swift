import Foundation
import Darwin
import AppKit
import CryptoKit
import ScreenplayDomain

/// Legacy project media: immutable PNGs beside the JSON, with portable relative references.
enum BoardImageStorage {
    static let folder = "Board Images"
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func read(_ version: BoardImageVersion) throws -> Data {
        guard version.fileURL.isFileURL,
              let size = try version.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(contentsOf: version.fileURL)
        guard BoardImageAPI.validPNG(data), digest(data) == version.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    static func store(_ data: Data, beside documentURL: URL) throws -> URL {
        guard BoardImageAPI.validPNG(data) else { throw CocoaError(.fileReadCorruptFile) }
        let directory = documentURL.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = directory.appendingPathComponent(digest(data) + ".png")
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        if let existing = try? Data(contentsOf: url), existing == data { return url }
        // Write beside the destination, then publish in one step so a crash or full
        // disk never leaves a partial PNG under its final content-addressed name.
        let temporary = directory.appendingPathComponent(".board-image-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        if FileManager.default.fileExists(atPath: url.path) {
            // The name is the content hash, so different bytes mean an earlier damaged write.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            do { try FileManager.default.linkItem(at: temporary, to: url) } catch {
                // exFAT, FAT, and some network volumes have no hard links: use an exclusive rename.
                if !FileManager.default.fileExists(atPath: url.path),
                   renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL)) == 0 { return url }
                // Another writer may have published the same image first.
                guard let existing = try? Data(contentsOf: url), existing == data else { throw error }
            }
        }
        return url
    }

    /// Copies readable image versions that live outside the destination's Board Images
    /// folder beside it. Unreadable versions keep their reference and are counted.
    static func gathered(_ document: ScreenplayOSDocument, beside url: URL) -> (document: ScreenplayOSDocument, unavailable: Int) {
        var result = document
        var unavailable = 0
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(folder).standardizedFileURL
        for board in result.boardFrames.indices {
            for index in result.boardFrames[board].imageVersions.indices {
                let version = result.boardFrames[board].imageVersions[index]
                guard version.fileURL.isFileURL,
                      version.fileURL.deletingLastPathComponent().standardizedFileURL != directory else { continue }
                do {
                    result.boardFrames[board].imageVersions[index].fileURL = try store(read(version), beside: url)
                } catch {
                    unavailable += 1
                }
            }
        }
        return (result, unavailable)
    }
    static func resolved(_ document: ScreenplayOSDocument, at url: URL) throws -> ScreenplayOSDocument {
        var result = document
        for board in result.boardFrames.indices {
            for index in result.boardFrames[board].imageVersions.indices {
                let reference = result.boardFrames[board].imageVersions[index].fileURL
                guard reference.scheme == nil else { continue }
                let path = reference.path
                let components = path.split(separator: "/", omittingEmptySubsequences: false)
                guard components.count == 2, components[0] == Substring(folder), !components[1].isEmpty,
                      components[1] != ".", components[1] != "..", reference.query == nil, reference.fragment == nil else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                let absolute = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(path)
                guard absolute.resolvingSymlinksInPath().standardizedFileURL == absolute.standardizedFileURL else { throw CocoaError(.fileReadInvalidFileName) }
                result.boardFrames[board].imageVersions[index].fileURL = absolute
            }
        }
        return result
    }
    static func portableReferences(_ document: ScreenplayOSDocument, at url: URL) -> ScreenplayOSDocument {
        var result = document
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(folder).standardizedFileURL
        for board in result.boardFrames.indices {
            for index in result.boardFrames[board].imageVersions.indices {
                let image = result.boardFrames[board].imageVersions[index].fileURL
                if image.isFileURL && image.deletingLastPathComponent().standardizedFileURL == directory {
                    var components = URLComponents()
                    components.path = folder + "/" + image.lastPathComponent
                    if let relative = components.url { result.boardFrames[board].imageVersions[index].fileURL = relative }
                }
            }
        }
        return result
    }
    static func export(_ document: ScreenplayOSDocument, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".board-export-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let file = staging.appendingPathComponent("Project.open-screenplay.json")
        var copy = document
        for board in copy.boardFrames.indices {
            for index in copy.boardFrames[board].imageVersions.indices {
                let version = copy.boardFrames[board].imageVersions[index]
                do { copy.boardFrames[board].imageVersions[index].fileURL = try store(read(version), beside: file) }
                catch { throw DialogueServiceError(message: "Could not include board \(copy.boardFrames[board].frameNumber), image \(version.id): \(version.fileURL.lastPathComponent). No portable copy was created.") }
            }
        }
        let encoded = try JSONEncoder.screenplayOSEncoder().encode(portableReferences(copy, at: file))
        try encoded.write(to: file, options: .withoutOverwriting)
        try fm.moveItem(at: staging, to: destination)
    }
}

@MainActor extension ScreenplayViewModel {
    func exportPortableProject() {
        guard let document, packageEditor == nil, !portableExportInProgress else { return }
        let panel = NSSavePanel()
        panel.title = "Export portable project folder"
        panel.nameFieldStringValue = "ScreenplayOS Project"
        panel.message = "Includes the current screenplay and every board-image version. Share the entire folder. Named snapshots and other linked media are not included. Choose a new folder name."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        portableExportInProgress = true
        portableExportStatus = "Copying screenplay and board images…"
        Task { @MainActor in
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do { try BoardImageStorage.export(document, to: url); return nil }
                catch { return error.localizedDescription }
            }.value
            portableExportInProgress = false
            portableExportStatus = failure ?? "Portable project copied to \(url.path)"
        }
    }
}
