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
    let id = UUID()
    let title: String
    let filename: String
    let paragraphs: [Paragraph]
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
    private static let payloadNames: Set<String> = ["manifest.json", "screenplay.json", "notes.json", "shots.json", "extensions.json", "film/outline.json", "film/boards.json", "film/edit.json", "film/production.json", "film/proposals.json", "film/activity.json"]

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
              Set(inventory.keys).isSubset(of: payloadNames),
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
        // Detect changes over the read interval; this is not an exclusive lock.
        for (name, data) in observed {
            guard try Data(contentsOf: package.appendingPathComponent(name)) == data else { throw PackagePreviewError.check(#line) }
        }
        return PackagePreview(title: title.isEmpty ? "Untitled Screenplay" : title, filename: package.lastPathComponent, paragraphs: paragraphs)
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
            Text("Script text preview. Page layout, production locks, and filmmaking views aren’t shown.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
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
            Divider()
            Text(preview.filename).font(.caption).foregroundStyle(.secondary).padding(10)
        }.frame(minWidth: 660, idealWidth: 820, minHeight: 440, idealHeight: 600)
    }
}
