import AppKit
import CryptoKit
import Foundation
import SwiftUI

struct PackagePreview: Identifiable {
    struct Paragraph: Identifiable {
        let id: UUID
        let type: String
        let text: String
    }
    struct BoardTake: Identifiable {
        let id: UUID
        let order: Int
        let imageData: Data
        let model: String
        let selected: Bool
    }
    struct Board: Identifiable {
        let id: UUID
        let label: String
        let duration: Double
        let takes: [BoardTake]
        var selectedTake: BoardTake? { takes.first(where: \.selected) }
    }
    let id = UUID()
    let title: String
    let filename: String
    let paragraphs: [Paragraph]
    let boards: [Board]
    var scenes: [Paragraph] { paragraphs.filter { $0.type == "scene_heading" } }
}

enum PackagePreviewError: LocalizedError {
    case invalid
    case check(Int)
    var errorDescription: String? {
        "This package could not be opened safely. It may be incomplete, changed, unsupported, or too large for this preview. Your current screenplay has not been replaced."
    }
}

enum PackagePreviewReader {
    private static let payloadNames: Set<String> = ["manifest.json", "screenplay.json", "notes.json", "shots.json", "extensions.json", "film/outline.json", "film/boards.json", "film/media.json", "film/edit.json", "film/production.json", "film/proposals.json", "film/activity.json"]

    static func read(_ inputPackage: URL) throws -> PackagePreview {
        guard try inputPackage.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PackagePreviewError.check(#line) }
        let package = inputPackage.resolvingSymlinksInPath()
        let fm = FileManager.default
        guard package.pathExtension.lowercased() == "screenplay",
              (try package.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
              (try package.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw PackagePreviewError.check(#line) }
        var bytesRead = 0
        var observed: [String: Data] = [:]
        func readFile(_ name: String) throws -> Data {
            var url = package
            for component in name.split(separator: "/") {
                guard component != "..", component != "." else { throw PackagePreviewError.check(#line) }
                url.appendPathComponent(String(component))
                guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PackagePreviewError.check(#line) }
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 32 * 1024 * 1024 else { throw PackagePreviewError.check(#line) }
            let data = try Data(contentsOf: url)
            bytesRead += data.count
            guard data.count == size, bytesRead <= 128 * 1024 * 1024 else { throw PackagePreviewError.check(#line) }
            observed[name] = data
            return data
        }
        func object(_ data: Data) throws -> [String: Any] {
            try UniqueJSONKeys.check(data)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PackagePreviewError.check(#line) }
            return result
        }
        func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let project = try object(readFile("project.json"))
        guard project["format"] as? String == "open-screenplay-project",
              project["format_version"] as? String == "0.1-draft",
              let head = project["head"] as? [String: Any],
              let inventory = head["files"] as? [String: [String: Any]],
              inventory.keys.allSatisfy({ payloadNames.contains($0) || validAttachmentName($0) }),
              ["manifest.json", "screenplay.json", "extensions.json"].allSatisfy({ inventory[$0] != nil }) else { throw PackagePreviewError.check(#line) }
        let expected = Set(inventory.keys).union(["project.json", "provenance/source.json", "provenance/candidate.json"])
        guard let enumerator = fm.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else { throw PackagePreviewError.check(#line) }
        var found = Set<String>()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw PackagePreviewError.check(#line) }
            if values.isRegularFile == true {
                let normalizedPath = url.resolvingSymlinksInPath().path
                guard normalizedPath.hasPrefix(package.path + "/") else { throw PackagePreviewError.check(#line) }
                let name = String(normalizedPath.dropFirst(package.path.count + 1))
                if name == ".DS_Store" { continue }
                found.insert(name)
            }
        }
        guard found == expected else { throw PackagePreviewError.check(#line) }
        for (name, entry) in inventory {
            let data = try readFile(name)
            guard let count = entry["bytes"] as? NSNumber,
                  CFGetTypeID(count) != CFBooleanGetTypeID(), count.doubleValue == Double(data.count),
                  entry["sha256"] as? String == digest(data) else { throw PackagePreviewError.check(#line) }
        }
        let original = try readFile("provenance/source.json")
        let metadata = try object(readFile("provenance/candidate.json"))
        guard metadata["candidate_version"] as? String == "0.1",
              metadata["source_sha256"] as? String == digest(original) else { throw PackagePreviewError.check(#line) }
        let manifest = try object(observed["manifest.json"]!)
        let screenplay = try object(observed["screenplay.json"]!)
        guard manifest["format"] as? String == "open-screenplay", manifest["format_version"] as? String == "1.0",
              let documentID = screenplay["id"] as? String, UUID(uuidString: documentID) != nil,
              manifest["document_id"] as? String == documentID, project["screenplay_id"] as? String == documentID,
              let projectID = project["project_id"] as? String, UUID(uuidString: projectID) != nil,
              let title = manifest["title"] as? String,
              let elements = screenplay["elements"] as? [[String: Any]] else { throw PackagePreviewError.check(#line) }
        var seen = Set<UUID>()
        let paragraphs = try elements.map { element -> PackagePreview.Paragraph in
            guard let rawID = element["id"] as? String, let id = UUID(uuidString: rawID), seen.insert(id).inserted,
                  let type = element["type"] as? String, let text = element["text"] as? String else { throw PackagePreviewError.check(#line) }
            return PackagePreview.Paragraph(id: id, type: type, text: text)
        }
        let boards = try boardPreviews(observed: observed, projectID: projectID, object: object, digest: digest)
        // Detect changes over the read interval; this is not an exclusive lock.
        for (name, data) in observed {
            guard try Data(contentsOf: package.appendingPathComponent(name)) == data else { throw PackagePreviewError.check(#line) }
        }
        return PackagePreview(title: title.isEmpty ? "Untitled Screenplay" : title, filename: package.lastPathComponent, paragraphs: paragraphs, boards: boards)
    }

    private static func validAttachmentName(_ name: String) -> Bool {
        name.range(of: #"^attachments/boards/[0-9a-f]{64}\.png$"#, options: .regularExpression) != nil
    }

    private static func boardPreviews(observed: [String: Data], projectID: String, object: (Data) throws -> [String: Any],
                                      digest: (Data) -> String) throws -> [PackagePreview.Board] {
        let attachmentNames = Set(observed.keys.filter(validAttachmentName))
        guard let mediaData = observed["film/media.json"] else {
            guard attachmentNames.isEmpty else { throw PackagePreviewError.check(#line) }
            return []
        }
        guard let boardData = observed["film/boards.json"],
              let boards = try object(boardData)["boards"] as? [[String: Any]] else { throw PackagePreviewError.check(#line) }
        let registry = try object(mediaData)
        guard let version = registry["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 1,
              registry["project_id"] as? String == projectID,
              let assets = registry["media"] as? [[String: Any]] else { throw PackagePreviewError.check(#line) }
        var boardMap: [UUID: [String: Any]] = [:]
        for board in boards {
            guard let id = (board["id"] as? String).flatMap(UUID.init), boardMap.updateValue(board, forKey: id) == nil else {
                throw PackagePreviewError.check(#line)
            }
        }
        var used = Set<String>(), seenAssets = Set<UUID>(), seenBoards = Set<UUID>(), seenVersions = Set<UUID>()
        var result: [PackagePreview.Board] = []
        for asset in assets {
            guard let assetID = (asset["id"] as? String).flatMap(UUID.init), seenAssets.insert(assetID).inserted,
                  let boardID = (asset["board_id"] as? String).flatMap(UUID.init), seenBoards.insert(boardID).inserted,
                  let board = boardMap[boardID],
                  asset["shot_id"] as? String == board["shot_id"] as? String,
                  let versions = asset["versions"] as? [[String: Any]], !versions.isEmpty,
                  let legacy = board["image_versions"] as? [[String: Any]], versions.count == legacy.count,
                  let label = board["label"] as? String, let duration = board["duration_seconds"] as? NSNumber,
                  CFGetTypeID(duration) != CFBooleanGetTypeID() else { throw PackagePreviewError.check(#line) }
            let selected = asset["selected_version_id"] as? String
            guard selected == board["selected_image_id"] as? String else { throw PackagePreviewError.check(#line) }
            var takes: [PackagePreview.BoardTake] = []
            for (order, pair) in zip(versions, legacy).enumerated() {
                let version = pair.0, original = pair.1
                guard let idText = version["id"] as? String, idText == original["id"] as? String,
                      let id = UUID(uuidString: idText), seenVersions.insert(id).inserted,
                      let path = version["path"] as? String, validAttachmentName(path),
                      let sha = version["sha256"] as? String, path == "attachments/boards/\(sha).png",
                      sha == original["sha256"] as? String, let data = observed[path], digest(data) == sha,
                      let byteCount = version["bytes"] as? NSNumber, byteCount.intValue == data.count,
                      version["media_type"] as? String == "image/png", let width = version["width"] as? NSNumber,
                      let height = version["height"] as? NSNumber,
                      let dimensions = pngDimensions(data), dimensions.0 == width.intValue, dimensions.1 == height.intValue,
                      (version["prompt"] as? String ?? "") == (original["prompt"] as? String ?? ""),
                      (version["model"] as? String ?? "") == (original["model"] as? String ?? "")
                else { throw PackagePreviewError.check(#line) }
                used.insert(path)
                takes.append(.init(id: id, order: order, imageData: data,
                                   model: version["model"] as? String ?? "Local board", selected: idText == selected))
            }
            guard takes.filter(\.selected).count == (selected == nil ? 0 : 1) else { throw PackagePreviewError.check(#line) }
            result.append(.init(id: boardID, label: label, duration: duration.doubleValue, takes: takes))
        }
        guard used == attachmentNames else { throw PackagePreviewError.check(#line) }
        return result
    }

    private static func pngDimensions(_ data: Data) -> (Int, Int)? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, Array(bytes[0..<8]) == [137,80,78,71,13,10,26,10],
              Array(bytes[12..<16]) == [73,72,68,82] else { return nil }
        func value(_ offset: Int) -> Int { bytes[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) } }
        let width = value(16), height = value(20)
        return (1...32768).contains(width) && (1...32768).contains(height) ? (width, height) : nil
    }
}

/// Detect duplicate decoded keys before Foundation projects the JSON for display.
/// JSONSerialization validates syntax; this bounded scanner only checks key uniqueness.
private struct UniqueJSONKeys {
    var bytes: [UInt8]
    var index = 0
    static func check(_ data: Data) throws {
        _ = try JSONSerialization.jsonObject(with: data)
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.value(depth: 0)
    }
    mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func string() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            if bytes[index] == 92 { index += 2; continue }
            if bytes[index] == 34 {
                index += 1
                guard let decoded = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String else { throw PackagePreviewError.check(#line) }
                return decoded
            }
            index += 1
        }
        throw PackagePreviewError.check(#line)
    }
    mutating func value(depth: Int) throws {
        guard depth < 128 else { throw PackagePreviewError.check(#line) }
        whitespace()
        guard index < bytes.count else { throw PackagePreviewError.check(#line) }
        if bytes[index] == 34 { _ = try string(); return }
        if bytes[index] == 123 {
            index += 1; whitespace(); var keys = Set<String>()
            if bytes[index] == 125 { index += 1; return }
            while true {
                whitespace(); let key = try string()
                guard keys.insert(key).inserted else { throw PackagePreviewError.check(#line) }
                whitespace(); index += 1
                try value(depth: depth + 1); whitespace()
                if bytes[index] == 125 { index += 1; return }
                index += 1
            }
        }
        if bytes[index] == 91 {
            index += 1; whitespace()
            if bytes[index] == 93 { index += 1; return }
            while true {
                try value(depth: depth + 1); whitespace()
                if bytes[index] == 93 { index += 1; return }
                index += 1
            }
        }
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
    }
}

struct PackagePreviewView: View {
    let preview: PackagePreview
    let close: () -> Void
    @State private var navigationRequest: UUID?
    @State private var targetScene: UUID?
    @State private var mode = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title).font(.headline)
                    Text("Read-only · Experimental package").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close Preview", action: close).keyboardShortcut(.cancelAction)
            }.padding(16)
            Text("Read-only package inspection. Editing, page locks, and other filmmaking views aren’t available.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            if !preview.boards.isEmpty {
                Picker("Preview", selection: $mode) { Text("Script").tag(0); Text("Boards").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            if mode == 1 && !preview.boards.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(preview.boards) { board in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(board.label).font(.headline); Spacer(); Text(String(format: "%.1fs", board.duration)).font(.caption.monospacedDigit()) }
                                if let take = board.selectedTake, let image = NSImage(data: take.imageData) {
                                    Image(nsImage: image).resizable().scaledToFit().background(Color.black)
                                    Text("Selected Take \(take.order + 1) · \(take.model)").font(.caption).foregroundStyle(.secondary)
                                }
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(board.takes) { take in
                                            VStack(alignment: .leading, spacing: 4) {
                                                if let image = NSImage(data: take.imageData) { Image(nsImage: image).resizable().scaledToFit().frame(width: 150, height: 84).background(Color.black) }
                                                Text("Take \(take.order + 1)\(take.selected ? " · IN USE" : "")").font(.caption2.weight(take.selected ? .semibold : .regular))
                                            }
                                        }
                                    }
                                }
                            }.padding(12).background(StudioAppearance.recess).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }.padding(16)
                }.accessibilityLabel("Read-only packaged boards")
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.scenes) { scene in
                                Button {
                                    targetScene = scene.id
                                    navigationRequest = UUID()
                                } label: {
                                    Text(scene.text.isEmpty ? "Untitled Scene" : scene.text)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.borderless)
                            }
                        }.padding(12)
                    }.frame(width: 200).accessibilityLabel("Preview scenes")
                    Divider()
                    ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if preview.paragraphs.isEmpty { Text("This screenplay is empty.").foregroundStyle(.secondary) }
                            ForEach(preview.paragraphs) { paragraph in
                                Text(paragraph.text.isEmpty ? " " : paragraph.text)
                                    .font(.system(size: 14, design: .monospaced))
                                    .fontWeight(paragraph.type == "scene_heading" ? .semibold : .regular)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(paragraph.id)
                            }
                        }.padding(24)
                    }.accessibilityLabel("Read-only screenplay text")
                        .onChange(of: navigationRequest) { _ in
                            if let targetScene { proxy.scrollTo(targetScene, anchor: .top) }
                        }
                }
            }
            }
            Divider()
            Text(preview.filename).font(.caption).foregroundStyle(.secondary).padding(10)
        }.frame(minWidth: 660, idealWidth: 820, minHeight: 440, idealHeight: 600)
    }
}
