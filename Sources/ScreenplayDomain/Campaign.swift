import Foundation

public enum CampaignError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public struct CampaignBrief: Codable, Equatable {
    public var brand: String
    public var objective: String
    public var audience: String
    public var keyMessage: String
    public var mandatoryRequirements: String
    public init(brand: String = "", objective: String = "", audience: String = "", keyMessage: String = "", mandatoryRequirements: String = "") {
        self.brand = brand; self.objective = objective; self.audience = audience
        self.keyMessage = keyMessage; self.mandatoryRequirements = mandatoryRequirements
    }
}

public struct CampaignDeliverable: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var durationSeconds: Int
    public var aspectRatio: String
    public var market: String
    public var language: String
    public var linkedShotIDs: [UUID]
    public init(id: UUID = UUID(), name: String = "", durationSeconds: Int = 30, aspectRatio: String = "16:9", market: String = "", language: String = "", linkedShotIDs: [UUID] = []) {
        self.id = id; self.name = name; self.durationSeconds = durationSeconds; self.aspectRatio = aspectRatio
        self.market = market; self.language = language; self.linkedShotIDs = linkedShotIDs
    }
}

public struct CampaignAssumption: Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var sourceLabel: String
    public var sourceReference: String
    public init(id: UUID = UUID(), text: String = "", sourceLabel: String = "", sourceReference: String = "") {
        self.id = id; self.text = text; self.sourceLabel = sourceLabel; self.sourceReference = sourceReference
    }
}

public struct CampaignDraft: Codable, Equatable {
    public var brief: CampaignBrief
    public var deliverables: [CampaignDeliverable]
    public var assumptions: [CampaignAssumption]
    public var agency: CampaignAgencyWorkspace?
    public init(brief: CampaignBrief = .init(), deliverables: [CampaignDeliverable] = [], assumptions: [CampaignAssumption] = [], agency: CampaignAgencyWorkspace? = nil) {
        self.brief = brief; self.deliverables = deliverables; self.assumptions = assumptions; self.agency = agency
    }
    public func validate() throws {
        try agency?.validate()
        try campaignUnique(deliverables.map(\.id), "deliverables")
        try campaignUnique(assumptions.map(\.id), "assumptions")
        for item in deliverables {
            guard (1...86400).contains(item.durationSeconds) else { throw CampaignError.invalid("Deliverable duration must be 1–86400 whole seconds.") }
            try campaignUnique(item.linkedShotIDs, "linked shots")
        }
    }
    public func validateForBaseline() throws {
        try validate()
        guard !brief.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !brief.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !deliverables.isEmpty,
              deliverables.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CampaignError.invalid("A baseline needs a brand, objective, and at least one deliverable with a name and aspect ratio.")
        }
    }
}

public enum CampaignApprovalScope: String, Codable, CaseIterable { case creative, production, spend }

/// A local record of evidence supplied by a person. This does not verify identity or execute spending.
public struct CampaignDecision: Codable, Equatable, Identifiable {
    public let id: UUID
    public let baselineID: UUID
    public let scope: CampaignApprovalScope
    public let approver: String
    public let evidence: String
    public let createdAt: Date
    public let spendCeilingMinorUnits: Int64?
    public let currencyCode: String?
    fileprivate func validate() throws {
        guard !approver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CampaignError.invalid("Record the approver and approval evidence.")
        }
        if scope != .spend {
            guard spendCeilingMinorUnits == nil, currencyCode == nil else { throw CampaignError.invalid("Only spend approval can include a spend ceiling.") }
        } else if let amount = spendCeilingMinorUnits {
            guard amount >= 0, let currencyCode, currencyCode.count == 3,
                  currencyCode.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else {
                throw CampaignError.invalid("Use a nonnegative integer ceiling and a three-letter uppercase currency code.")
            }
        } else { throw CampaignError.invalid("Spend approval requires an explicit ceiling and currency.") }
    }
}

public struct CampaignBaseline: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let draft: CampaignDraft
    public let sources: [CampaignSourceSnapshot]
}

public struct CampaignLedger: Codable, Equatable {
    public static let currentVersion = 1
    public let version: Int
    public let projectID: UUID
    public var draft: CampaignDraft
    public private(set) var baselines: [CampaignBaseline]
    public private(set) var decisions: [CampaignDecision]
    public init(projectID: UUID, draft: CampaignDraft = .init()) {
        version = Self.currentVersion; self.projectID = projectID; self.draft = draft; baselines = []; decisions = []
    }
    enum CodingKeys: String, CodingKey { case version, projectID, draft, baselines, decisions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        draft = try c.decode(CampaignDraft.self, forKey: .draft)
        baselines = try c.decode([CampaignBaseline].self, forKey: .baselines)
        decisions = try c.decode([CampaignDecision].self, forKey: .decisions)
        _ = try validated()
    }
    @discardableResult public func validated() throws -> Self {
        guard version == Self.currentVersion else { throw CampaignError.invalid("Unsupported campaign ledger version.") }
        try draft.validate()
        try campaignUnique(baselines.map(\.id), "baselines")
        try campaignUnique(decisions.map(\.id), "decisions")
        for baseline in baselines {
            guard !baseline.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CampaignError.invalid("Name the baseline.") }
            try baseline.draft.validateForBaseline()
            try CampaignSourceSnapshot.validate(baseline.sources)
        }
        for decision in decisions {
            guard baselines.contains(where: { $0.id == decision.baselineID }) else { throw CampaignError.invalid("Approval references an unknown baseline.") }
            try decision.validate()
        }
        return self
    }
    @discardableResult public mutating func freeze(name: String, document: ScreenplayOSDocument, at date: Date = Date()) throws -> CampaignBaseline {
        _ = try validated()
        guard projectID == document.project.id else { throw CampaignError.invalid("Campaign belongs to a different project.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CampaignError.invalid("Name the baseline.") }
        try draft.validateForBaseline()
        let baseline = CampaignBaseline(id: UUID(), name: name, createdAt: date, draft: draft, sources: try CampaignSourceSnapshot.capture(document))
        baselines.append(baseline)
        return baseline
    }
    public func compare(baselineID: UUID, document: ScreenplayOSDocument) throws -> [CampaignChange] {
        _ = try validated()
        guard projectID == document.project.id else { throw CampaignError.invalid("Campaign belongs to a different project.") }
        guard let baseline = baselines.first(where: { $0.id == baselineID }) else { throw CampaignError.invalid("Baseline not found.") }
        return try CampaignChange.compare(baseline: baseline, draft: draft, sources: CampaignSourceSnapshot.capture(document), projectID: projectID)
    }
    /// Appends the current proposal with its immutable identity and evidence,
    /// assigning record time only on confirmation. Its decision identity makes
    /// replay fail after success, including after persistence and reopening.
    @discardableResult public mutating func confirmDecision(_ preview: CampaignDecisionPreview,
                                                            baselineID: UUID,
                                                            document: ScreenplayOSDocument,
                                                            at date: Date = Date()) throws -> CampaignDecision {
        guard baselineID == preview.baseline.id,
              try preview.contextMatches(ledger: self, document: document) else {
            throw CampaignError.invalid("The approval context changed. Review the selected baseline and preview the local record again.")
        }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw CampaignError.invalid("The local approval record needs a valid confirmation time.")
        }
        // Reuse current validation rules without replacing the preview's exact
        // identity, evidence, or ceiling with newly captured values.
        var checked = self
        let proposed = preview.decision
        _ = try checked.recordDecision(baselineID: proposed.baselineID, scope: proposed.scope,
            approver: proposed.approver, evidence: proposed.evidence, document: document,
            spendCeilingMinorUnits: proposed.spendCeilingMinorUnits,
            currencyCode: proposed.currencyCode, at: date)
        let recorded = CampaignDecision(id: proposed.id, baselineID: proposed.baselineID,
            scope: proposed.scope, approver: proposed.approver, evidence: proposed.evidence,
            createdAt: date, spendCeilingMinorUnits: proposed.spendCeilingMinorUnits,
            currencyCode: proposed.currencyCode)
        decisions.append(recorded)
        return recorded
    }

    @discardableResult public mutating func recordDecision(baselineID: UUID, scope: CampaignApprovalScope, approver: String, evidence: String, document: ScreenplayOSDocument, spendCeilingMinorUnits: Int64? = nil, currencyCode: String? = nil, at date: Date = Date()) throws -> CampaignDecision {
        guard try compare(baselineID: baselineID, document: document).isEmpty else {
            throw CampaignError.invalid("Sources changed or links are unresolved. Review and freeze a current baseline before recording approval.")
        }
        let decision = CampaignDecision(id: UUID(), baselineID: baselineID, scope: scope, approver: approver, evidence: evidence, createdAt: date, spendCeilingMinorUnits: spendCeilingMinorUnits, currencyCode: currencyCode)
        try decision.validate()
        decisions.append(decision)
        return decision
    }
}

func campaignUnique(_ ids: [UUID], _ label: String) throws {
    guard Set(ids).count == ids.count else { throw CampaignError.invalid("Duplicate identifiers in \(label).") }
}
func campaignJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
