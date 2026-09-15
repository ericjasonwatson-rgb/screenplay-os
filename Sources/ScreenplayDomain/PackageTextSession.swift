import Foundation

/// Conservative in-memory command boundary for a complete, minimal package snapshot.
/// The caller must supply every file. This is not a disk loader or a package writer.
public struct PackageTextSession {
    public enum Failure: Error { case unsupportedContent, invalidIdentity, staleRevision, missingElement }
    public private(set) var revision = UUID()
    public let originalFiles: [String: Data]
    private var session: PreservedJSONSession
    public struct Paragraph: Identifiable { public let id: UUID; public let type: String }
    public static let supportedTypes = ["scene_heading", "action", "character", "dialogue", "parenthetical", "transition", "general", "shot"]
    public private(set) var paragraphs: [Paragraph]
    private var indexes: [UUID: Int]
    public var screenplayBytes: Data { session.document.data }
    public var canUndo: Bool { session.canUndo }
    public var canRedo: Bool { session.canRedo }
    public var undoHistoryID: UUID? { session.undoHistoryID }
    public var redoHistoryID: UUID? { session.redoHistoryID }
    public var historyIDs: Set<UUID> { session.historyIDs }
    public var historyBytes: Int { session.historyBytes }

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
        self.paragraphs = elements.map { Paragraph(id: UUID(uuidString: $0["id"] as! String)!, type: $0["type"] as! String) }

    }

    public func text(for elementID: UUID) throws -> String {
        try session.document.string(at: path(for: elementID))
    }

    public mutating func replaceText(elementID: UUID, expectedRevision: UUID, expectedText: String, replacement: String, historyGroup: UUID? = nil) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        let path = try path(for: elementID)
        let before = screenplayBytes
        try session.replaceString(at: path, expected: expectedText, with: replacement, historyGroup: historyGroup)
        if screenplayBytes != before { revision = UUID() }
    }

    public mutating func changeType(elementID: UUID, expectedRevision: UUID, type: String) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        guard Self.supportedTypes.contains(type) else { throw Failure.unsupportedContent }
        guard let index = indexes[elementID] else { throw Failure.missingElement }
        let path: [PreservedJSON.Component] = [.key("elements"), .index(index), .key("type")]
        var candidate = session.document
        try candidate.replaceString(at: path, expected: candidate.string(at: path), with: type)
        try commit(candidate)
    }

    /// Insert after a stable identity, or at the beginning when nil. IDs survive redo.
    @discardableResult public mutating func insert(after: UUID?, expectedRevision: UUID, type: String = "action", text: String = "", id: UUID = UUID()) throws -> UUID {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        guard Self.supportedTypes.contains(type) else { throw Failure.unsupportedContent }
        guard indexes[id] == nil else { throw Failure.invalidIdentity }
        let index: Int
        if let after { guard let found = indexes[after] else { throw Failure.missingElement }; index = found + 1 }
        else { index = 0 }
        var candidate = session.document
        var items = try candidate.arrayValues(at: [.key("elements")])
        items.insert(try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "type": type, "text": text], options: [.sortedKeys]), at: index)
        try candidate.replaceArray(at: [.key("elements")], with: items)
        try commit(candidate)
        return id
    }

    public mutating func delete(elementID: UUID, expectedRevision: UUID) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        guard let index = indexes[elementID] else { throw Failure.missingElement }
        var candidate = session.document
        var items = try candidate.arrayValues(at: [.key("elements")]); items.remove(at: index)
        try candidate.replaceArray(at: [.key("elements")], with: items)
        try commit(candidate)
    }

    /// One undo transaction retains the old identity on the prefix and creates the suffix.
    @discardableResult public mutating func split(elementID: UUID, expectedRevision: UUID, prefix: String, suffix: String, nextType: String) throws -> UUID {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        var candidateSession = self
        try candidateSession.replaceText(elementID: elementID, expectedRevision: candidateSession.revision,
                                         expectedText: candidateSession.text(for: elementID), replacement: prefix)
        let id = try candidateSession.insert(after: elementID, expectedRevision: candidateSession.revision, type: nextType, text: suffix)
        try commit(candidateSession.session.document)
        return id
    }
    /// Replace a contiguous paragraph span in one transaction, retaining the first ID.
    @discardableResult public mutating func editSpan(startID: UUID, endID: UUID, expectedRevision: UUID,
        prefix: String, replacement: String, suffix: String, splitType: String? = nil, historyGroup: UUID? = nil) throws -> UUID {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        guard let first = indexes[startID], let last = indexes[endID], first <= last else { throw Failure.missingElement }
        if first == last && splitType == nil {
            try replaceText(elementID: startID, expectedRevision: expectedRevision,
                            expectedText: text(for: startID), replacement: prefix + replacement + suffix, historyGroup: historyGroup)
            return startID
        }
        var candidate = self
        let removed = paragraphs[(first + 1)..<(last + 1)].map(\.id)
        for id in removed { try candidate.delete(elementID: id, expectedRevision: candidate.revision) }
        let text = prefix + replacement + (splitType == nil ? suffix : "")
        try candidate.replaceText(elementID: startID, expectedRevision: candidate.revision,
                                  expectedText: candidate.text(for: startID), replacement: text)
        var selected = startID
        if let splitType {
            selected = try candidate.insert(after: startID, expectedRevision: candidate.revision, type: splitType, text: suffix)
        }
        try commit(candidate.session.document)
        return selected
    }

    private mutating func commit(_ candidate: PreservedJSON) throws {
        guard candidate.data != screenplayBytes else { return }
        var files = originalFiles; files["screenplay.json"] = candidate.data
        let validated = try Self(files: files)
        session.commit(candidate); revision = UUID()
        paragraphs = validated.paragraphs; indexes = validated.indexes
    }

    public mutating func undo() {
        guard canUndo else { return }; session.undo(); revision = UUID(); refreshProjection()
    }
    public mutating func redo() {
        guard canRedo else { return }; session.redo(); revision = UUID(); refreshProjection()
    }
    private mutating func refreshProjection() {
        // History only contains previously validated states. Cache identity lookup
        // so rendering each row does not parse the whole screenplay repeatedly.
        let root = try! JSONSerialization.jsonObject(with: screenplayBytes) as! [String: Any]
        paragraphs = (root["elements"] as! [[String: Any]]).map {
            Paragraph(id: UUID(uuidString: $0["id"] as! String)!, type: $0["type"] as! String)
        }
        indexes = Dictionary(uniqueKeysWithValues: paragraphs.enumerated().map { ($0.element.id, $0.offset) })
    }
    private func path(for id: UUID) throws -> [PreservedJSON.Component] {
        guard let index = indexes[id] else { throw Failure.missingElement }
        return [.key("elements"), .index(index), .key("text")]
    }
}
