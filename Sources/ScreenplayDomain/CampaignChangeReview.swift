import Foundation

/// Transient export choices, never persisted in the campaign ledger.
public struct CampaignChangeReportOptions: Equatable {
    public let includeFullEvidence: Bool
    public let maximumUTF8Bytes: Int
    public init(includeFullEvidence: Bool = false, maximumUTF8Bytes: Int = 2_000_000) {
        self.includeFullEvidence = includeFullEvidence
        self.maximumUTF8Bytes = maximumUTF8Bytes
    }
}

/// An immutable, non-Codable review of the exact bytes offered for local export.
/// Export must validate this object, not reconstruct a report from newer state.
public struct CampaignChangeReportPreview: Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let baselineID: UUID
    public let generatedAt: Date
    public let options: CampaignChangeReportOptions
    public let data: Data
    public var text: String { String(decoding: data, as: UTF8.self) }
    public let changeCount: Int
    public let unresolvedCount: Int
    private let context: Data

    fileprivate init(id: UUID, projectID: UUID, baselineID: UUID, generatedAt: Date,
                     options: CampaignChangeReportOptions, data: Data,
                     changeCount: Int, unresolvedCount: Int, context: Data) {
        self.id = id; self.projectID = projectID; self.baselineID = baselineID
        self.generatedAt = generatedAt; self.options = options; self.data = data
        self.changeCount = changeCount; self.unresolvedCount = unresolvedCount; self.context = context
    }

    public func contextMatches(ledger: CampaignLedger, document: ScreenplayOSDocument) throws -> Bool {
        guard ledger.projectID == projectID, document.project.id == projectID,
              let baseline = ledger.baselines.first(where: { $0.id == baselineID }) else { return false }
        _ = try ledger.validated()
        return try context == Self.contextBytes(ledger: ledger, baseline: baseline, document: document)
    }

    public func validatedData(ledger: CampaignLedger, baselineID: UUID,
                              document: ScreenplayOSDocument) throws -> Data {
        guard baselineID == self.baselineID, try contextMatches(ledger: ledger, document: document) else {
            throw CampaignError.invalid("The report context changed. Review a new report preview before exporting.")
        }
        return data
    }

    fileprivate static func contextBytes(ledger: CampaignLedger, baseline: CampaignBaseline,
                                         document: ScreenplayOSDocument) throws -> Data {
        struct Context: Encodable {
            let projectID: UUID
            let projectTitle: String
            let baseline: CampaignBaseline
            let draft: CampaignDraft
            let sources: [CampaignSourceSnapshot]
            let decisions: [CampaignDecision]
        }
        // Data equality, not String/Equatable: normalization-only edits count.
        return Data(try campaignJSON(Context(projectID: ledger.projectID,
            projectTitle: document.project.metadata.title, baseline: baseline, draft: ledger.draft,
            sources: CampaignSourceSnapshot.capture(document), decisions: ledger.decisions)).utf8)
    }
}

extension CampaignLedger {
    public func previewChangeReport(baselineID: UUID, document: ScreenplayOSDocument,
                                     options: CampaignChangeReportOptions = .init(),
                                     at date: Date = Date()) throws -> CampaignChangeReportPreview {
        guard (1...2_000_000).contains(options.maximumUTF8Bytes) else {
            throw CampaignError.invalid("Report byte limit must be between 1 and 2000000.")
        }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw CampaignError.invalid("The report needs a valid generation time.")
        }
        let changes = try compare(baselineID: baselineID, document: document)
        guard let baseline = baselines.first(where: { $0.id == baselineID }),
              baseline.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CampaignError.invalid("The selected baseline needs a valid creation time.")
        }
        let context = try CampaignChangeReportPreview.contextBytes(ledger: self, baseline: baseline, document: document)
        let id = UUID()
        var data = Data()
        func append(_ text: String) throws {
            let bytes = Data(text.utf8)
            guard bytes.count <= options.maximumUTF8Bytes - data.count else {
                throw CampaignError.invalid("The report exceeds the selected UTF-8 byte limit. Nothing was truncated or exported.")
            }
            data.append(bytes)
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try append("CampaignOS change review\nPreview ID: \(id.uuidString)\n")
        try append("CONFIDENTIAL: Not automatically redacted. Neither mode is client-safe.\nNot a quote, approval, or spend authority. Human review is required.\n")
        try append("Scope: Tracked campaign, screenplay, shot and board metadata only; selected image metadata, not media analysis. Agency document extraction is bounded; original documents need human review. PDF import is not supported. This is not exhaustive reconciliation.\n")
        try append("Mode: \(options.includeFullEvidence ? "Full evidence (explicit opt-in)" : "Summary (before/after payloads excluded)")\n")
        try append("Project: \(campaignReportQuoted(document.project.metadata.title))\nProject ID: \(projectID.uuidString)\n")
        try append("Baseline: \(campaignReportQuoted(baseline.name))\nBaseline ID: \(baseline.id.uuidString)\n")
        try append("Baseline created: \(formatter.string(from: baseline.createdAt))\nGenerated: \(formatter.string(from: date))\n")
        try append("Change rows: \(changes.count)\nUnresolved rows: \(changes.filter(\.unresolved).count)\n")
        if changes.isEmpty { try append("No tracked changes or unresolved rows detected within this scope.\n") }
        for (index, change) in changes.enumerated() {
            // Only generated labels and identifiers here. Never use before/after
            // (including unresolved diagnostic payloads) in the summary branch.
            try append("\nChange \(index + 1): \(campaignReportQuoted(change.title))\nKind: \(change.sourceKind.rawValue)\nSource ID: \(change.sourceID.uuidString)\nChange ID: \(campaignReportQuoted(change.id))\n")
            try append("Unresolved: \(change.unresolved ? "YES — unresolved evidence or links" : "no")\nAffected deliverables: \(change.affectedDeliverableIDs.count)\n")
            if change.affectedDeliverableIDs.isEmpty { try append("None linked; impact is not established.\n") }
            for affectedID in change.affectedDeliverableIDs {
                let current = draft.deliverables.first { $0.id == affectedID }
                let old = baseline.draft.deliverables.first { $0.id == affectedID }
                try append("- ID: \(affectedID.uuidString); current name: \(current.map { campaignReportQuoted($0.name) } ?? "[not present]"); baseline name: \(old.map { campaignReportQuoted($0.name) } ?? "[not present]")\n")
            }
            if options.includeFullEvidence {
                // Byte-length framing distinguishes raw evidence from report
                // metadata even when evidence contains headings or delimiters.
                try append("Before evidence (\(change.before.utf8.count) UTF-8 bytes; raw content follows):\n")
                try append(change.before)
                try append("\nAfter evidence (\(change.after.utf8.count) UTF-8 bytes; raw content follows):\n")
                try append(change.after)
                try append("\nEnd evidence for change \(index + 1).\n")
            }
        }
        return CampaignChangeReportPreview(id: id, projectID: projectID, baselineID: baselineID,
            generatedAt: date, options: options, data: data, changeCount: changes.count,
            unresolvedCount: changes.filter(\.unresolved).count, context: context)
    }
}

/// Keep all user-controlled metadata on a single quoted line. Escape separators,
/// controls and bidi formatting as well as ordinary JSON special characters.
private func campaignReportQuoted(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22: result += "\\\""
        case 0x5C: result += "\\\\"
        case 0x0A: result += "\\n"
        case 0x0D: result += "\\r"
        case 0x09: result += "\\t"
        case 0...0x1F, 0x7F...0x9F, 0x2028...0x202E, 0x2066...0x2069:
            result += String(format: "\\u{%04X}", scalar.value)
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}
