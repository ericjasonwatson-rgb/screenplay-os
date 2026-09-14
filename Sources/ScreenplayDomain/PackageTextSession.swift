import Foundation

/// Conservative in-memory command boundary for a complete, minimal package snapshot.
/// The caller must supply every file. This is not a disk loader or a package writer.
public struct PackageTextSession {
    public enum Failure: Error { case unsupportedContent, invalidIdentity, staleRevision, missingElement }
    public private(set) var revision = UUID()
    public let originalFiles: [String: Data]
    private var session: PreservedJSONSession
    private let indexes: [UUID: Int]
    public var screenplayBytes: Data { session.document.data }
    public var canUndo: Bool { session.canUndo }
    public var canRedo: Bool { session.canRedo }

    public init(files: [String: Data]) throws {
        // Companions can contain locks or references that this command cannot repair.
        guard Set(files.keys) == ["manifest.json", "screenplay.json"],
              let manifestBytes = files["manifest.json"], let scriptBytes = files["screenplay.json"] else {
            throw Failure.unsupportedContent
        }
        let manifest = try PreservedJSON(manifestBytes)
        let script = try PreservedJSON(scriptBytes)
        guard let metadata = try JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any],
              Set(metadata.keys) == ["format", "format_version", "document_id", "title", "author", "created_at", "modified_at"],
              metadata.values.allSatisfy({ $0 is String }),
              try manifest.string(at: [.key("format")]) == "open-screenplay",
              try manifest.string(at: [.key("format_version")]) == "1.0",
              let documentID = UUID(uuidString: try manifest.string(at: [.key("document_id")])) else {
            throw Failure.unsupportedContent
        }
        guard let root = try JSONSerialization.jsonObject(with: scriptBytes) as? [String: Any],
              Set(root.keys) == ["id", "elements"],
              let elements = root["elements"] as? [[String: Any]] else { throw Failure.unsupportedContent }
        guard UUID(uuidString: try script.string(at: [.key("id")])) == documentID else { throw Failure.invalidIdentity }
        var indexes: [UUID: Int] = [:]
        let types: Set<String> = ["scene_heading", "action", "character", "dialogue", "parenthetical", "transition", "general", "shot"]
        for (index, element) in elements.enumerated() {
            // Any additional field may carry formatting, revision marks, or parsed references.
            guard Set(element.keys) == ["id", "type", "text"],
                  let type = element["type"] as? String, types.contains(type), element["text"] is String else {
                throw Failure.unsupportedContent
            }
            guard let rawID = element["id"] as? String, let id = UUID(uuidString: rawID), indexes[id] == nil else {
                throw Failure.invalidIdentity
            }
            indexes[id] = index
        }
        self.originalFiles = files
        self.session = try PreservedJSONSession(scriptBytes)
        self.indexes = indexes
    }

    public func text(for elementID: UUID) throws -> String {
        try session.document.string(at: path(for: elementID))
    }

    public mutating func replaceText(elementID: UUID, expectedRevision: UUID, expectedText: String, replacement: String) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        let path = try path(for: elementID)
        let before = screenplayBytes
        try session.replaceString(at: path, expected: expectedText, with: replacement)
        if screenplayBytes != before { revision = UUID() }
    }

    public mutating func undo() {
        guard canUndo else { return }; session.undo(); revision = UUID()
    }
    public mutating func redo() {
        guard canRedo else { return }; session.redo(); revision = UUID()
    }
    private func path(for id: UUID) throws -> [PreservedJSON.Component] {
        guard let index = indexes[id] else { throw Failure.missingElement }
        return [.key("elements"), .index(index), .key("text")]
    }
}
