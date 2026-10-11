import Foundation

public enum ContinuityEntityKind: String, Codable, CaseIterable, Sendable {
    case character, location, prop, style
}

public enum ContinuityProposalStatus: String, Codable, CaseIterable, Sendable {
    case proposed, adopted, rejected
}

public struct ScriptEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let elementID: UUID
    public let elementIndex: Int
    public let sceneHeadingID: UUID?
    public let sceneHeading: String?
    public let exactText: String

    public init(
        id: UUID = UUID(), elementID: UUID, elementIndex: Int,
        sceneHeadingID: UUID?, sceneHeading: String?, exactText: String
    ) {
        self.id = id
        self.elementID = elementID
        self.elementIndex = elementIndex
        self.sceneHeadingID = sceneHeadingID
        self.sceneHeading = sceneHeading
        self.exactText = exactText
    }
}

public struct ContinuityProposal: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ContinuityEntityKind
    public var name: String
    public var aliases: [String]
    public var evidence: [ScriptEvidence]
    public var status: ContinuityProposalStatus

    public init(
        id: UUID = UUID(), kind: ContinuityEntityKind, name: String,
        aliases: [String] = [], evidence: [ScriptEvidence],
        status: ContinuityProposalStatus = .proposed
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.evidence = evidence
        self.status = status
    }

    public var occurrenceCount: Int { evidence.count }
    public var firstAppearance: ScriptEvidence? { evidence.min { $0.elementIndex < $1.elementIndex } }
}

public enum PerformerClassification: String, Codable, CaseIterable, Sendable {
    case fictional, realPerformer = "real_performer"
}

public struct ContinuityBibleEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ContinuityEntityKind
    public var name: String
    public var aliases: [String]
    public var linkedElementIDs: [UUID]
    public var description: String
    public var visualNotes: String
    public var wardrobeNotes: String
    public var voiceNotes: String
    public var negativeConstraints: [String]
    public var performerClassification: PerformerClassification?

    public init(
        id: UUID = UUID(), kind: ContinuityEntityKind, name: String,
        aliases: [String] = [], linkedElementIDs: [UUID] = [], description: String = "",
        visualNotes: String = "", wardrobeNotes: String = "", voiceNotes: String = "",
        negativeConstraints: [String] = [], performerClassification: PerformerClassification? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.linkedElementIDs = linkedElementIDs
        self.description = description
        self.visualNotes = visualNotes
        self.wardrobeNotes = wardrobeNotes
        self.voiceNotes = voiceNotes
        self.negativeConstraints = negativeConstraints
        self.performerClassification = performerClassification
    }
}

public struct ContinuityBibleLedger: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let projectID: UUID
    public var proposals: [ContinuityProposal]
    public var entries: [ContinuityBibleEntry]

    public init(
        version: Int = Self.currentVersion, projectID: UUID,
        proposals: [ContinuityProposal] = [], entries: [ContinuityBibleEntry] = []
    ) {
        self.version = version
        self.projectID = projectID
        self.proposals = proposals
        self.entries = entries
    }

    @discardableResult
    public mutating func adopt(proposalID: UUID, as name: String? = nil) throws -> ContinuityAdoptionUndo {
        guard let index = proposals.firstIndex(where: { $0.id == proposalID }) else {
            throw ContinuityBibleError.proposalNotFound
        }
        guard proposals[index].status == .proposed else { throw ContinuityBibleError.proposalNotPending }
        let proposal = proposals[index]
        let resolvedName = (name ?? proposal.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else { throw ContinuityBibleError.invalidName }
        let entry = ContinuityBibleEntry(
            kind: proposal.kind,
            name: resolvedName,
            aliases: proposal.aliases,
            linkedElementIDs: proposal.evidence.reduce(into: []) { ids, item in
                if !ids.contains(item.elementID) { ids.append(item.elementID) }
            },
            performerClassification: proposal.kind == .character ? .fictional : nil
        )
        proposals[index].status = .adopted
        entries.append(entry)
        return ContinuityAdoptionUndo(proposalID: proposal.id, entryID: entry.id)
    }

    public mutating func undo(_ token: ContinuityAdoptionUndo) throws {
        guard let proposalIndex = proposals.firstIndex(where: { $0.id == token.proposalID }),
              let entryIndex = entries.firstIndex(where: { $0.id == token.entryID }),
              proposals[proposalIndex].status == .adopted else {
            throw ContinuityBibleError.undoTargetNotFound
        }
        entries.remove(at: entryIndex)
        proposals[proposalIndex].status = .proposed
    }
}

public struct ContinuityAdoptionUndo: Codable, Equatable, Sendable {
    public let proposalID: UUID
    public let entryID: UUID
}

public enum ContinuityBibleError: Error, Equatable {
    case proposalNotFound, proposalNotPending, invalidName, undoTargetNotFound
}

public enum ContinuityExtractor {
    public static func proposals(from screenplay: Screenplay) -> [ContinuityProposal] {
        var currentHeading: ScreenplayElement?
        var characters: [String: (String, [ScriptEvidence])] = [:]
        var locations: [String: (String, [ScriptEvidence])] = [:]
        var propMentions: [String: (String, [ScriptEvidence])] = [:]

        for (index, element) in screenplay.elements.enumerated() {
            if element.type == .sceneHeading { currentHeading = element }
            let evidence = ScriptEvidence(
                elementID: element.id, elementIndex: index,
                sceneHeadingID: currentHeading?.id, sceneHeading: currentHeading?.text,
                exactText: element.text
            )
            switch element.type {
            case .character:
                let name = characterBaseName(element.text)
                append(name: name, evidence: evidence, to: &characters)
            case .sceneHeading:
                let name = sceneLocation(element.text)
                append(name: name, evidence: evidence, to: &locations)
            case .action:
                for phrase in uppercasePhrases(element.text) {
                    append(name: phrase, evidence: evidence, to: &propMentions)
                }
            default:
                break
            }
        }

        let characterKeys = Set(characters.keys)
        let locationWords = Set(locations.values.flatMap { $0.0.split(separator: " ").map(normalizationKey) })
        let props = propMentions.filter { key, value in
            Set(value.1.map(\.elementID)).count >= 2 && !characterKeys.contains(key)
                && !locationWords.contains(key) && !excludedPropKeys.contains(key)
        }

        return makeProposals(.character, characters)
            + makeProposals(.location, locations)
            + makeProposals(.prop, props)
    }

    public static func characterBaseName(_ cue: String) -> String {
        var value = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\s*\([^()]+\)\s*$"#
        while let range = value.range(of: pattern, options: .regularExpression) {
            value.removeSubrange(range)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sceneLocation(_ heading: String) -> String {
        var value = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = #"^(?i:(?:INT\.?/EXT\.?|EXT\.?/INT\.?|I/E\.?|INT\.?|EXT\.?|EST\.?))\s*"#
        if let range = value.range(of: prefix, options: .regularExpression) { value.removeSubrange(range) }
        if let range = value.range(of: #"\s+(?:-|–|—)\s+[^-–—]+$"#, options: .regularExpression) {
            value.removeSubrange(range)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func append(
        name: String, evidence: ScriptEvidence,
        to groups: inout [String: (String, [ScriptEvidence])]
    ) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let key = normalizationKey(clean)
        if groups[key] == nil { groups[key] = (clean, []) }
        groups[key]?.1.append(evidence)
    }

    private static func makeProposals(
        _ kind: ContinuityEntityKind, _ groups: [String: (String, [ScriptEvidence])]
    ) -> [ContinuityProposal] {
        groups.values.map { ContinuityProposal(kind: kind, name: $0.0, evidence: $0.1) }
            .sorted {
                let lhs = $0.firstAppearance?.elementIndex ?? .max
                let rhs = $1.firstAppearance?.elementIndex ?? .max
                return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
            }
    }

    private static func normalizationKey<S: StringProtocol>(_ value: S) -> String {
        String(value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func uppercasePhrases(_ text: String) -> [String] {
        let separators = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'’.-" )).inverted
        let words = text.components(separatedBy: separators).filter { !$0.isEmpty }
        var result: [String] = []
        var run: [String] = []
        func flush() {
            guard !run.isEmpty else { return }
            result.append(run.prefix(4).joined(separator: " "))
            run.removeAll(keepingCapacity: true)
        }
        for word in words {
            let hasLetter = word.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            if hasLetter && word == word.uppercased() && word.count > 1 { run.append(word) } else { flush() }
        }
        flush()
        return result
    }

    private static let excludedPropKeys: Set<String> = [
        "A", "AN", "AND", "AT", "CUT", "CUT TO", "DAY", "EXT", "FADE", "FADE IN", "FADE OUT",
        "INT", "INTO", "LATER", "MOMENTS LATER", "NIGHT", "ON", "THE", "TO"
    ]
}
