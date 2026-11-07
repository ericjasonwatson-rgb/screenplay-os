import Foundation

/// Navigation within the existing Campaign panel, never a command or permission.
public enum CampaignReviewDestination: String, CaseIterable {
    case brief, agencySources, coverage, assumptions, baseline, decisions, report
}

/// Transient guidance, not a persisted completion flag or approval score.
public struct CampaignReviewChecklistItem: Identifiable {
    public var id: String { destination.rawValue }
    public let destination: CampaignReviewDestination
    public let title: String
    public let summary: String
    public let details: [String]
    public let needsAttention: Bool
}

/// Counts describe local evidence for one exact baseline, not verified authority.
public struct CampaignReviewDecisionRecords {
    public let baselineID: UUID
    public let creativeCount: Int
    public let productionCount: Int
    public let spendCount: Int
    public let isHistorical: Bool
    public let hasUnresolvedReview: Bool
}

/// A read-only, non-Codable assessment of current Campaign navigation needs.
/// The caller must display errors, rather than substituting an empty checklist.
/// Reuse `changes` for the comparison UI: a selected baseline captures sources
/// only once. Pre-baseline guidance does not capture or compare script/media state.
public struct CampaignReviewChecklist {
    public static let comparisonScope = "Tracked campaign, screenplay, shot and board metadata, and imported agency evidence only. Selected image identity/hash metadata is compared, not actual media. Original documents and semantic coverage need human review; this is not exhaustive reconciliation."
    public static let decisionBoundary = "Local records do not verify identity, grant permission or authorize spending. No requirement to record all three scopes is implied."

    public let items: [CampaignReviewChecklistItem]
    public let nextStep: CampaignReviewChecklistItem
    public let selectedBaseline: CampaignBaseline?
    public let changes: [CampaignChange]?
    public var changeCount: Int? { changes?.count }
    public var trackedChangeCount: Int? { changes?.filter { !$0.unresolved }.count }
    public var unresolvedCount: Int? { changes?.filter(\.unresolved).count }
    public let decisionRecords: CampaignReviewDecisionRecords?
    public let agencyWarnings: [CampaignAgencyWarning]
    public let missingBaselineFields: [String]
    public let missingShotLinkCount: Int
    public let unlinkedDeliverableCount: Int

    public init(ledger: CampaignLedger, document: ScreenplayOSDocument,
                selectedBaselineID: UUID?) throws {
        guard ledger.projectID == document.project.id else {
            throw CampaignError.invalid("Campaign belongs to a different project.")
        }
        guard document.project.screenplayID == document.screenplay.id else {
            throw CampaignError.invalid("Project screenplay identity does not match its screenplay.")
        }
        _ = try ledger.validated()
        let baseline: CampaignBaseline?
        if let selectedBaselineID {
            guard let selected = ledger.baselines.first(where: { $0.id == selectedBaselineID }) else {
                throw CampaignError.invalid("The selected baseline was not found. Select an existing baseline before continuing review.")
            }
            guard selected.createdAt.timeIntervalSinceReferenceDate.isFinite else {
                throw CampaignError.invalid("The selected baseline needs a valid creation time.")
            }
            baseline = selected
        } else {
            baseline = nil
        }

        // Source capture/validation belongs to a real comparison. Avoid a full
        // script/media scan on every pre-baseline field edit, and never invent a
        // synthetic baseline just to produce a purported readiness result.
        let comparison: [CampaignChange]?
        if let baseline {
            comparison = try CampaignChange.compare(baseline: baseline, draft: ledger.draft,
                sources: CampaignSourceSnapshot.capture(document), projectID: ledger.projectID)
        } else {
            comparison = nil
        }
        let trackedCount = comparison?.filter { !$0.unresolved }.count ?? 0
        let unresolvedCount = comparison?.filter(\.unresolved).count ?? 0
        selectedBaseline = baseline
        changes = comparison

        // Concrete field prompts explain the existing baseline rule. The rule
        // itself remains validateForBaseline(); unknown future failures propagate.
        let draft = ledger.draft
        var missing: [String] = []
        func isBlank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isBlank(draft.brief.brand) { missing.append("Enter the brand.") }
        if isBlank(draft.brief.objective) { missing.append("Enter the campaign objective.") }
        if draft.deliverables.isEmpty { missing.append("Add at least one deliverable.") }
        for (index, deliverable) in draft.deliverables.enumerated() {
            let reference = "Deliverable \(index + 1) (\(deliverable.id.uuidString))"
            if isBlank(deliverable.name) { missing.append("\(reference): enter a name.") }
            if isBlank(deliverable.aspectRatio) { missing.append("\(reference): enter an aspect ratio.") }
        }
        do {
            try draft.validateForBaseline()
            // Do not let diagnostic prompts silently become stricter than the
            // authoritative rule if that rule changes later.
            missing = []
        } catch {
            guard !missing.isEmpty else { throw error }
        }
        missingBaselineFields = missing

        let warnings = draft.agency?.warnings(draft: draft) ?? []
        agencyWarnings = warnings
        let unreviewed = warnings.filter { $0.sourceKind == .agencyDocument }.count
        let reconciliation = warnings.filter { $0.sourceKind == .agencyCitation }.count
        let sourceCount = draft.agency?.latestRevisions.count ?? 0

        // This row assesses deliverable-to-shot identities only. Full source
        // warnings come from the authoritative comparison, when one is selected.
        let shotIDs = Set(document.shots.map(\.id))
        var missingLinks: [String] = []
        var missingLinkCount = 0
        for (index, deliverable) in draft.deliverables.enumerated() {
            let missingIDs = deliverable.linkedShotIDs.filter { !shotIDs.contains($0) }
            missingLinkCount += missingIDs.count
            for id in missingIDs {
                missingLinks.append("Deliverable \(index + 1) (\(deliverable.id.uuidString)): missing linked shot \(id.uuidString).")
            }
        }
        let unlinkedCount = draft.deliverables.filter { $0.linkedShotIDs.isEmpty }.count
        missingShotLinkCount = missingLinkCount
        unlinkedDeliverableCount = unlinkedCount

        let records: CampaignReviewDecisionRecords?
        if let baseline {
            let decisions = ledger.decisions.filter { $0.baselineID == baseline.id }
            records = CampaignReviewDecisionRecords(baselineID: baseline.id,
                creativeCount: decisions.filter { $0.scope == .creative }.count,
                productionCount: decisions.filter { $0.scope == .production }.count,
                spendCount: decisions.filter { $0.scope == .spend }.count,
                isHistorical: trackedCount > 0, hasUnresolvedReview: unresolvedCount > 0)
        } else {
            records = nil
        }
        decisionRecords = records

        let brief = CampaignReviewChecklistItem(destination: .brief,
            title: missing.isEmpty ? "Review brief and deliverables" : "Complete baseline fields",
            summary: missing.isEmpty ? "Required baseline fields are present. Review the agreed scope and bid assumptions." : "\(missing.count) required field action\(missing.count == 1 ? "" : "s") before freezing a baseline.",
            details: missing.isEmpty ? ["Field presence does not establish scope completeness or approval. Manual agency references and bid assumptions remain available."] : missing,
            needsAttention: !missing.isEmpty)
        let agency = CampaignReviewChecklistItem(destination: .agencySources,
            title: warnings.isEmpty ? "Agency sources are optional" : "Review agency evidence",
            summary: sourceCount == 0 ? "No imported agency sources. Manual references are supported." : "\(sourceCount) current source\(sourceCount == 1 ? "" : "s"); \(unreviewed) unreviewed; \(reconciliation) citation warning\(reconciliation == 1 ? "" : "s").",
            details: warnings.isEmpty ? ["Import only when useful. A local review note does not verify authenticity or approve campaign scope."] : warnings.map(\.message),
            needsAttention: !warnings.isEmpty)
        var coverageDetails = missingLinks
        coverageDetails.append("\(unlinkedCount) deliverable\(unlinkedCount == 1 ? " has" : "s have") no linked shots. Linking is optional; assess coverage manually.")
        coverageDetails.append("Links describe relationships, not semantic or exhaustive coverage. Inspect unlinked script changes and deliverable intent manually.")
        if baseline == nil {
            coverageDetails.append("Script, shot and board source-link warnings are shown in Baseline & Changes after selecting a frozen baseline.")
        } else {
            coverageDetails.append("Other unresolved source links, legacy ranges and selected-image warnings appear in the selected baseline comparison.")
        }
        let coverage = CampaignReviewChecklistItem(destination: .coverage,
            title: missingLinkCount == 0 ? "Review shot coverage manually" : "Resolve missing shot links",
            summary: "\(missingLinkCount) missing deliverable-to-shot link\(missingLinkCount == 1 ? "" : "s"). Coverage still needs human review.",
            details: coverageDetails, needsAttention: missingLinkCount > 0)
        let assumptionCount = draft.assumptions.count
        let assumptions = CampaignReviewChecklistItem(destination: .assumptions,
            title: "Review bid assumptions",
            summary: "\(assumptionCount) manual bid assumption\(assumptionCount == 1 ? "" : "s"). Record scope qualifications and document/version/page references when useful.",
            details: ["Assumptions are optional working evidence, not a quote, approval or promise of cost or schedule. Review whether the intended bid basis needs clarification."],
            needsAttention: false)

        let baselineItem: CampaignReviewChecklistItem
        if let baseline {
            baselineItem = CampaignReviewChecklistItem(destination: .baseline,
                title: comparison?.isEmpty == true ? "Inspect the selected baseline" : "Review baseline changes",
                summary: "\(trackedCount) tracked change\(trackedCount == 1 ? "" : "s"); \(unresolvedCount) unresolved review row\(unresolvedCount == 1 ? "" : "s").",
                details: ["Selected baseline: \(baseline.name)", "Baseline ID: \(baseline.id.uuidString)", Self.comparisonScope,
                    comparison?.isEmpty == true ? "No tracked changes or unresolved rows were detected within this scope. This is not approval." : "Review each change and unresolved row. After resolving the intended scope, freeze a new baseline when appropriate."],
                needsAttention: comparison?.isEmpty == false)
        } else {
            let hasBaselines = !ledger.baselines.isEmpty
            baselineItem = CampaignReviewChecklistItem(destination: .baseline,
                title: hasBaselines ? "Select a baseline to compare" : "Review scope, then freeze a baseline",
                summary: hasBaselines ? "No baseline is selected. Existing baselines and their records are not combined." : "No baseline exists. Review the brief, assumptions, coverage and any agency evidence before freezing.",
                details: [Self.comparisonScope, "Freezing captures a named scope snapshot. It does not approve it."],
                needsAttention: true)
        }

        let recordSummary: String
        var recordDetails = [Self.decisionBoundary]
        if let records {
            recordSummary = "Selected baseline only: creative \(records.creativeCount), production \(records.productionCount), spend \(records.spendCount)."
            recordDetails.append("Baseline ID: \(records.baselineID.uuidString)")
            if records.isHistorical {
                recordDetails.append("Historical records: the current tracked scope differs from this baseline. These records do not carry forward to revised scope.")
            } else if records.hasUnresolvedReview {
                recordDetails.append("Unresolved evidence or links need review. Existing records do not resolve those warnings.")
            } else {
                recordDetails.append("Inspect existing evidence or record separately received decisions only when appropriate. Zero records is not a failed approval gate.")
            }
        } else {
            recordSummary = "Select a baseline to inspect its separate creative, production and spend records."
        }
        let decisions = CampaignReviewChecklistItem(destination: .decisions,
            title: "Inspect local decision records", summary: recordSummary,
            details: recordDetails, needsAttention: false)
        let report = CampaignReviewChecklistItem(destination: .report,
            title: "Review a private change report",
            summary: baseline == nil ? "Select a baseline before previewing a report." : "Preview the selected baseline's report and inspect it before any export.",
            details: ["Reports may contain confidential information. Neither summary nor full evidence is automatically client-safe.",
                "Export requires a separate review and save action. Keep a separate private backup for recovery."],
            needsAttention: false)

        let rows = [brief, agency, coverage, assumptions, baselineItem, decisions, report]
        items = rows
        // Advice only: every destination merely reveals an existing section.
        // Missing optional records or unlinked coverage never become approval gates.
        nextStep = rows.first(where: \.needsAttention) ?? report
    }
}
