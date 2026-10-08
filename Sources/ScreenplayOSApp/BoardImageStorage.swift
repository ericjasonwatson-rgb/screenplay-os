import Foundation
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
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteFileExists) }
        } else { try data.write(to: url, options: .withoutOverwriting) }
        return url
    }
    static func resolved(_ document: OpenScreenplayDocument, at url: URL) throws -> OpenScreenplayDocument {
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
    static func portableReferences(_ document: OpenScreenplayDocument, at url: URL) -> OpenScreenplayDocument {
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
    static func export(_ document: OpenScreenplayDocument, to destination: URL) throws {
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
        let encoded = try JSONEncoder.openScreenplayEncoder().encode(portableReferences(copy, at: file))
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
