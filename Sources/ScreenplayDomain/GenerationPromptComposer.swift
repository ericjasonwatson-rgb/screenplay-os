import CryptoKit
import Foundation

public enum GenerationPromptComposerError: Error, Equatable {
    case invalidInstruction
    case missingScriptContext
    case projectMismatch
}

public struct GenerationPromptComposition: Equatable {
    public let target: GenerationTarget
    public let request: GenerationRequestSnapshot
    public let continuityEntryIDs: [UUID]
    public let consentRecordIDs: [UUID]

    public init(
        target: GenerationTarget,
        request: GenerationRequestSnapshot,
        continuityEntryIDs: [UUID],
        consentRecordIDs: [UUID]
    ) {
        self.target = target
        self.request = request
        self.continuityEntryIDs = continuityEntryIDs
        self.consentRecordIDs = consentRecordIDs
    }
}

/// Builds the complete creative request before a generation job is created.
/// The result is deterministic for the same inputs and contains no credentials.
public enum GenerationPromptComposer {
    public static func compose(
        capability: GenerationCapability,
        instruction: String,
        targetKind: GenerationTargetKind,
        targetID: UUID,
        sceneElements: [ScreenplayElement],
        shot: Shot? = nil,
        continuity: ContinuityBibleLedger,
        projectID: UUID,
        references: [GenerationReference] = [],
        parameters: [String: String] = [:],
        evaluatedAt: Date
    ) throws -> GenerationPromptComposition {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { throw GenerationPromptComposerError.invalidInstruction }
        guard !sceneElements.isEmpty else { throw GenerationPromptComposerError.missingScriptContext }
        guard continuity.projectID == projectID else { throw GenerationPromptComposerError.projectMismatch }

        let elementIDs = Set(sceneElements.map(\.id))
        let entries = continuity.entries
            .filter { !Set($0.linkedElementIDs).isDisjoint(with: elementIDs) }
            .sorted(by: entryOrder)

        let scope: PerformerConsentScope? = switch capability {
        case .image, .video: .likenessGeneration
        case .voice: .voiceCloning
        case .text: nil
        }
        var consentIDs: Set<UUID> = []
        if let scope {
            for entry in entries where entry.kind == .character {
                let ids = try ContinuityGenerationGate.authorize(
                    entryID: entry.id, scope: scope, at: evaluatedAt, ledger: continuity
                )
                consentIDs.formUnion(ids)
            }
        }
        let sortedConsentIDs = consentIDs.sorted { $0.uuidString < $1.uuidString }
        let entryIDs = entries.map(\.id)
        let prompt = renderPrompt(instruction: instruction, sceneElements: sceneElements, shot: shot, entries: entries)
        let request = GenerationRequestSnapshot(
            prompt: prompt,
            references: references,
            parameters: parameters,
            continuityEntryIDs: entryIDs,
            consentRecordIDs: sortedConsentIDs
        )
        let revision = try sourceRevision(
            capability: capability,
            targetKind: targetKind,
            targetID: targetID,
            sceneElements: sceneElements,
            shot: shot,
            entries: entries,
            consentRecordIDs: sortedConsentIDs
        )
        return GenerationPromptComposition(
            target: .init(kind: targetKind, id: targetID, sourceRevision: revision),
            request: request,
            continuityEntryIDs: entryIDs,
            consentRecordIDs: sortedConsentIDs
        )
    }

    private static func renderPrompt(
        instruction: String,
        sceneElements: [ScreenplayElement],
        shot: Shot?,
        entries: [ContinuityBibleEntry]
    ) -> String {
        var sections = ["DIRECTING INTENT\n\(instruction)"]
        if let shot {
            sections.append([
                "SHOT",
                "Label: \(shot.label)",
                "Setup: \(shot.setup.rawValue)",
                "Notes: \(shot.notes.isEmpty ? "None" : shot.notes)"
            ].joined(separator: "\n"))
        }
        sections.append("COVERED SCREENPLAY\n" + sceneElements.map {
            "[\($0.type.rawValue)] \($0.text)"
        }.joined(separator: "\n"))
        if !entries.isEmpty {
            sections.append("ADOPTED CONTINUITY\n" + entries.map(renderEntry).joined(separator: "\n\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func renderEntry(_ entry: ContinuityBibleEntry) -> String {
        var fields = ["\(entry.kind.rawValue.uppercased()): \(entry.name)"]
        if !entry.aliases.isEmpty { fields.append("Aliases: \(entry.aliases.joined(separator: ", "))") }
        if !entry.description.isEmpty { fields.append("Description: \(entry.description)") }
        if !entry.visualNotes.isEmpty { fields.append("Visual: \(entry.visualNotes)") }
        if !entry.wardrobeNotes.isEmpty { fields.append("Wardrobe: \(entry.wardrobeNotes)") }
        if !entry.voiceNotes.isEmpty { fields.append("Voice: \(entry.voiceNotes)") }
        if !entry.negativeConstraints.isEmpty {
            fields.append("Do not: \(entry.negativeConstraints.joined(separator: "; "))")
        }
        return fields.joined(separator: "\n")
    }

    private static func entryOrder(_ left: ContinuityBibleEntry, _ right: ContinuityBibleEntry) -> Bool {
        if left.kind.rawValue != right.kind.rawValue { return left.kind.rawValue < right.kind.rawValue }
        if left.name != right.name { return left.name.utf8.lexicographicallyPrecedes(right.name.utf8) }
        return left.id.uuidString < right.id.uuidString
    }

    private struct RevisionPayload: Encodable {
        let capability: GenerationCapability
        let targetKind: GenerationTargetKind
        let targetID: UUID
        let sceneElements: [ScreenplayElement]
        let shot: Shot?
        let entries: [ContinuityBibleEntry]
        let consentRecordIDs: [UUID]

        enum CodingKeys: String, CodingKey {
            case capability, shot, entries
            case targetKind = "target_kind"
            case targetID = "target_id"
            case sceneElements = "scene_elements"
            case consentRecordIDs = "consent_record_ids"
        }
    }

    private static func sourceRevision(
        capability: GenerationCapability,
        targetKind: GenerationTargetKind,
        targetID: UUID,
        sceneElements: [ScreenplayElement],
        shot: Shot?,
        entries: [ContinuityBibleEntry],
        consentRecordIDs: [UUID]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = RevisionPayload(
            capability: capability, targetKind: targetKind, targetID: targetID,
            sceneElements: sceneElements, shot: shot, entries: entries,
            consentRecordIDs: consentRecordIDs
        )
        return SHA256.hash(data: try encoder.encode(payload)).map { String(format: "%02x", $0) }.joined()
    }
}
