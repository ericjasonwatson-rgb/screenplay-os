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
    public private(set) var typography: DocumentTypography
    public var settingsBytes: Data? { session.companion }
    public var currentFiles: [String: Data] {
        var files = originalFiles; files["screenplay.json"] = screenplayBytes; files["settings.json"] = settingsBytes
        return files
    }
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
        guard Set(files.keys).isSubset(of: ["manifest.json", "screenplay.json", "settings.json"]),
              let manifestBytes = files["manifest.json"], let scriptBytes = files["screenplay.json"] else {
            throw Failure.unsupportedContent
        }
        if let settings = files["settings.json"] {
            let preserved = try PreservedJSON(settings)
            guard let root = try JSONSerialization.jsonObject(with: settings) as? [String: Any], Set(root.keys) == ["formatting"] else { throw Failure.unsupportedContent }
            typography = try JSONDecoder().decode(DocumentTypography.self, from: preserved.valueData(at: [.key("formatting")]))
            guard typography.paper == "US_LETTER" else { throw Failure.unsupportedContent }
        } else { typography = try DocumentTypography() }
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
            guard Set(element.keys).isSubset(of: ["id", "type", "text", "runs"]),
                  let type = element["type"] as? String, types.contains(type), element["text"] is String else {
                throw Failure.unsupportedContent
            }
            guard let rawID = element["id"] as? String, let id = UUID(uuidString: rawID), indexes[id] == nil else {
                throw Failure.invalidIdentity
            }
            if let runs = element["runs"] {
                let decoded = try JSONDecoder().decode([StyledText.Run].self, from: JSONSerialization.data(withJSONObject: runs))
                _ = try StyledText(text: element["text"] as! String, runs: decoded)
            }
            indexes[id] = index
        }
        self.originalFiles = files
        self.session = try PreservedJSONSession(scriptBytes, companion: files["settings.json"])
        self.indexes = indexes
        self.paragraphs = elements.map { Paragraph(id: UUID(uuidString: $0["id"] as! String)!, type: $0["type"] as! String) }

    }

    public mutating func setTypography(_ value: DocumentTypography, expectedRevision: UUID) throws {
        guard revision == expectedRevision else { throw Failure.staleRevision }
        guard value.paper == "US_LETTER" else { throw Failure.unsupportedContent }
        guard value != typography else { return }
        var settings = try PreservedJSON(settingsBytes ?? Data("{}".utf8))
        try settings.setMember("formatting", at: [], value: JSONEncoder().encode(value))
        var files = currentFiles; files["settings.json"] = settings.data
        _ = try Self(files: files)
        session.commit(session.document, companion: settings.data)
        typography = value; revision = UUID()
    }

    public func text(for elementID: UUID) throws -> String {
        try session.document.string(at: path(for: elementID))
    }

    public func styledText(for id: UUID) throws -> StyledText {
        guard let index = indexes[id] else { throw Failure.missingElement }
        let item = try session.document.valueData(at: [.key("elements"), .index(index)])
        let object = try JSONSerialization.jsonObject(with: item) as! [String: Any]
        let runs = try object["runs"].map { try JSONDecoder().decode([StyledText.Run].self, from: JSONSerialization.data(withJSONObject: $0)) } ?? []
        return try StyledText(text: text(for: id), runs: runs)
    }
    private func writeStyled(_ value: StyledText, id: UUID, into candidate: inout PreservedJSON) throws {
        guard let index = indexes[id] else { throw Failure.missingElement }
        let path: [PreservedJSON.Component] = [.key("elements"), .index(index)]
        try candidate.replaceString(at: path + [.key("text")], expected: candidate.string(at: path + [.key("text")]), with: value.text)
        try candidate.setMember("runs", at: path, value: JSONEncoder().encode(value.runs))
    }
    public mutating func format(elementID: UUID, expectedRevision: UUID, range: Range<Int>, patch: StyledText.Style) throws {
        guard revision == expectedRevision else { throw Failure.staleRevision }
        var value = try styledText(for: elementID)
        let original = value
        try value.format(range, patch: patch)
        guard value != original else { return }
        var candidate = session.document
        try writeStyled(value, id: elementID, into: &candidate)
        try commit(candidate)
    }
    public mutating func formatSelection(_ selection: NSRange, expectedRevision: UUID, patch: StyledText.Style) throws {
        guard revision == expectedRevision else { throw Failure.staleRevision }
        guard selection.location >= 0, selection.length >= 0 else { throw Failure.unsupportedContent }
        let projection = paragraphs.map { try! text(for: $0.id) }.joined(separator: "\n")
        guard selection.location <= projection.utf16.count, selection.length <= projection.utf16.count - selection.location else { throw Failure.unsupportedContent }
        var candidate = self, offset = 0
        for paragraph in paragraphs {
            let value = try styledText(for: paragraph.id)
            let range = NSIntersectionRange(selection, NSRange(location: offset, length: value.text.utf16.count))
            if range.length > 0 {
                let local = NSRange(location: range.location - offset, length: range.length)
                try candidate.format(elementID: paragraph.id, expectedRevision: candidate.revision, range: value.scalarRange(fromUTF16: local), patch: patch)
            }
            offset += value.text.utf16.count + 1
        }
        try commit(candidate.session.document)
    }
    private func insertionStyle(_ value: StyledText, at offset: Int) -> StyledText.Style {
        let point = max(0, offset - 1)
        return value.resolvedRuns.first { point >= $0.start && point < $0.start + $0.length }?.style ?? .init()
    }

    public mutating func replaceText(elementID: UUID, expectedRevision: UUID, expectedText: String, replacement: String, historyGroup: UUID? = nil) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        let old = try styledText(for: elementID)
        guard old.text.unicodeScalars.elementsEqual(expectedText.unicodeScalars) else { throw Failure.staleRevision }
        if !old.runs.isEmpty {
            let a = Array(old.text), b = Array(replacement)
            var prefix = 0, suffix = 0
            while prefix < min(a.count, b.count), String(a[prefix]).unicodeScalars.elementsEqual(String(b[prefix]).unicodeScalars) { prefix += 1 }
            while suffix < min(a.count, b.count) - prefix, String(a[a.count - suffix - 1]).unicodeScalars.elementsEqual(String(b[b.count - suffix - 1]).unicodeScalars) { suffix += 1 }
            let start = String(a.prefix(prefix)).unicodeScalars.count
            let end = old.text.unicodeScalars.count - String(a.suffix(suffix)).unicodeScalars.count
            var value = old
            try value.replace(start..<end, with: String(b[prefix..<(b.count - suffix)]), style: insertionStyle(old, at: start))
            var candidate = session.document
            try writeStyled(value, id: elementID, into: &candidate)
            try commit(candidate, historyGroup: historyGroup)
            return
        }
        let path = try path(for: elementID)
        let before = screenplayBytes
        try session.replaceString(at: path, expected: expectedText, with: replacement, historyGroup: historyGroup)
        if screenplayBytes != before { revision = UUID() }
    }

    public struct TextMatch {
        public let elementID: UUID
        public let range: NSRange
        public let text: String
    }
    /// Literal matches within authored paragraphs; never crosses structural boundaries.
    public func find(_ query: String, caseSensitive: Bool = false) -> [TextMatch] {
        guard !query.isEmpty else { return [] }
        var matches: [TextMatch] = []
        for paragraph in paragraphs {
            guard let value = try? text(for: paragraph.id) else { continue }
            let source = value as NSString
            var offset = 0
            while offset < source.length {
                let range = source.range(of: query, options: caseSensitive ? [] : [.caseInsensitive],
                    range: NSRange(location: offset, length: source.length - offset))
                guard range.location != NSNotFound, range.length > 0 else { break }
                if source.rangeOfComposedCharacterSequences(for: range) == range {
                    matches.append(TextMatch(elementID: paragraph.id, range: range, text: source.substring(with: range)))
                }
                offset = NSMaxRange(range)
            }
        }
        return matches
    }
    /// Validate the entire request before publishing one exact-byte undo transaction.
    public mutating func replaceMatches(_ matches: [TextMatch], expectedRevision: UUID, replacement: String) throws {
        guard expectedRevision == revision else { throw Failure.staleRevision }
        var candidate = session.document
        for (id, edits) in Dictionary(grouping: matches, by: \.elementID) {
            let original = try text(for: id)
            var value = original
            var styled = try styledText(for: id)
            let hasStyles = !styled.runs.isEmpty
            var upper = (original as NSString).length
            for match in edits.sorted(by: { $0.range.location > $1.range.location }) {
                guard match.range.location >= 0, match.range.length > 0, NSMaxRange(match.range) <= upper,
                      let range = Range(match.range, in: value),
                      (value as NSString).rangeOfComposedCharacterSequences(for: match.range) == match.range,
                      value[range].unicodeScalars.elementsEqual(match.text.unicodeScalars) else { throw Failure.staleRevision }
                if hasStyles {
                    let scalar = try styled.scalarRange(fromUTF16: match.range)
                    try styled.replace(scalar, with: replacement, style: insertionStyle(styled, at: scalar.lowerBound))
                }
                value.replaceSubrange(range, with: replacement)
                upper = match.range.location
            }
            if hasStyles { try writeStyled(styled, id: id, into: &candidate) }
            else { try candidate.replaceString(at: path(for: id), expected: original, with: value) }
        }
        try commit(candidate)
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
        let original = try styledText(for: elementID)
        if !original.runs.isEmpty {
            return try editSpan(startID: elementID, endID: elementID, expectedRevision: expectedRevision,
                prefix: prefix, replacement: "", suffix: suffix, splitType: nextType)
        }
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
        let firstStyled = try styledText(for: startID), lastStyled = try styledText(for: endID)
        if !firstStyled.runs.isEmpty || !lastStyled.runs.isEmpty {
            guard firstStyled.text.unicodeScalars.starts(with: prefix.unicodeScalars),
                  lastStyled.text.unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed()),
                  first != last || prefix.unicodeScalars.count + suffix.unicodeScalars.count <= firstStyled.text.unicodeScalars.count else { throw Failure.staleRevision }
            let leading = try firstStyled.split(at: prefix.unicodeScalars.count).0
            let trailing = try lastStyled.split(at: lastStyled.text.unicodeScalars.count - suffix.unicodeScalars.count).1
            let insertion = try StyledText(text: replacement, runs: replacement.isEmpty ? [] : [.init(start: 0, length: replacement.unicodeScalars.count, style: insertionStyle(firstStyled, at: prefix.unicodeScalars.count))])
            var value = try leading.appending(insertion)
            if splitType == nil { value = try value.appending(trailing) }
            var candidate = self
            for id in paragraphs[(first + 1)..<(last + 1)].map(\.id) { try candidate.delete(elementID: id, expectedRevision: candidate.revision) }
            var document = candidate.session.document
            try candidate.writeStyled(value, id: startID, into: &document)
            try candidate.commit(document)
            var selected = startID
            if let splitType {
                selected = try candidate.insert(after: startID, expectedRevision: candidate.revision, type: splitType, text: trailing.text)
                document = candidate.session.document
                try candidate.writeStyled(trailing, id: selected, into: &document)
                try candidate.commit(document)
            }
            try commit(candidate.session.document, historyGroup: historyGroup)
            return selected
        }
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

    private mutating func commit(_ candidate: PreservedJSON, historyGroup: UUID? = nil) throws {
        guard candidate.data != screenplayBytes else { return }
        var files = currentFiles; files["screenplay.json"] = candidate.data
        let validated = try Self(files: files)
        session.commit(candidate, historyGroup: historyGroup); revision = UUID()
        paragraphs = validated.paragraphs; indexes = validated.indexes
    }

    public mutating func undo() {
        guard canUndo else { return }; session.undo(); revision = UUID(); refreshProjection()
    }
    public mutating func redo() {
        guard canRedo else { return }; session.redo(); revision = UUID(); refreshProjection()
    }
    private mutating func refreshProjection() {
        typography = try! Self(files: currentFiles).typography
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
