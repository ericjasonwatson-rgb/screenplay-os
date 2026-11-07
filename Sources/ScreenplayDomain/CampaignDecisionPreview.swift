import Foundation

/// A transient local-record proposal, not a signature, sharing consent, payment,
/// or provider authorization. Only a validated ledger can construct one.
/// Intentionally not Codable: pending confirmations never survive a relaunch.
public struct CampaignDecisionPreview: Identifiable {
    public var id: UUID { decision.id }
    public let projectID: UUID
    public let baseline: CampaignBaseline
    /// Immutable proposed fields. Its createdAt is preparation time only; the
    /// persisted record receives its timestamp when explicitly confirmed.
    public let decision: CampaignDecision
    private let context: Data

    fileprivate init(projectID: UUID, baseline: CampaignBaseline, decision: CampaignDecision,
                     context: Data) {
        self.projectID = projectID
        self.baseline = baseline
        self.decision = decision
        self.context = context
    }

    /// Byte equality deliberately avoids Swift's canonical Unicode equality.
    /// Includes the entire draft (and retained agency reviews), tracked sources,
    /// selected baseline, and decision history so newer decisions invalidate it.
    public func contextMatches(ledger: CampaignLedger, document: ScreenplayOSDocument) throws -> Bool {
        guard ledger.projectID == projectID, document.project.id == projectID,
              let current = ledger.baselines.first(where: { $0.id == baseline.id }) else { return false }
        _ = try ledger.validated()
        return try context == Self.contextBytes(ledger: ledger, baseline: current, document: document)
    }

    fileprivate static func contextBytes(ledger: CampaignLedger, baseline: CampaignBaseline,
                                         document: ScreenplayOSDocument) throws -> Data {
        struct Context: Encodable {
            let projectID: UUID
            let baseline: CampaignBaseline
            let draft: CampaignDraft
            let sources: [CampaignSourceSnapshot]
            let decisions: [CampaignDecision]
        }
        return Data(try campaignJSON(Context(projectID: ledger.projectID, baseline: baseline,
            draft: ledger.draft, sources: CampaignSourceSnapshot.capture(document),
            decisions: ledger.decisions)).utf8)
    }
}

extension CampaignLedger {
    /// Runs the existing decision rules against a copy. No ledger mutation or
    /// external action occurs until this exact proposal is explicitly confirmed.
    public func previewDecision(baselineID: UUID, scope: CampaignApprovalScope, approver: String,
                                evidence: String, document: ScreenplayOSDocument,
                                spendCeilingMinorUnits: Int64? = nil, currencyCode: String? = nil,
                                at date: Date = Date()) throws -> CampaignDecisionPreview {
        var candidate = self
        let decision = try candidate.recordDecision(baselineID: baselineID, scope: scope,
            approver: approver, evidence: evidence, document: document,
            spendCeilingMinorUnits: spendCeilingMinorUnits, currencyCode: currencyCode, at: date)
        guard let baseline = baselines.first(where: { $0.id == baselineID }) else {
            throw CampaignError.invalid("Baseline not found.")
        }
        return CampaignDecisionPreview(projectID: projectID, baseline: baseline, decision: decision,
            context: try CampaignDecisionPreview.contextBytes(ledger: self, baseline: baseline, document: document))
    }
}
