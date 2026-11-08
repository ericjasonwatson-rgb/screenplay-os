import SwiftUI
import ScreenplayDomain

/// Transient presentation context. No proposal is added to the campaign until
/// the user previews it, confirms it, and the session's atomic save succeeds.
struct CampaignAgencyReconciliationContext {
    let projectID: UUID
    let citation: CampaignAgencyCitation
    let originalRevision: CampaignAgencyRevision
    let currentRevision: CampaignAgencyRevision
    let review: CampaignAgencyReview
}

@MainActor
struct CampaignAgencyReconciliationView: View {
    @ObservedObject var session: CampaignWorkspaceSession
    let context: CampaignAgencyReconciliationContext
    let finish: () -> Void
    @State private var firstLine = ""
    @State private var lastLine = ""
    @State private var targetKind: CampaignAgencyTargetKind = .deliverable
    @State private var targetID: UUID?
    @State private var targetSnapshot: String?
    @State private var note = ""
    @State private var preview: CampaignAgencyCitationReplacementPreview?
    @State private var problem: String?
    @State private var contextInvalidated = false

    private var currentOriginalTarget: String? {
        try? session.ledger.draft.agencyTargetSnapshot(kind: context.citation.targetKind, id: context.citation.targetID)
    }
    private var proposedExcerpt: String? {
        guard let first = Int(firstLine), let last = Int(lastLine) else { return nil }
        return try? context.currentRevision.excerpt(firstLine: first, lastLine: last)
    }
    private var canPreview: Bool {
        !contextInvalidated && proposedExcerpt != nil && targetID != nil && targetSnapshot != nil
            && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isReadOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            evidenceComparison
            replacementEditor
                .disabled(contextInvalidated || session.isReadOnly)
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .accessibilityIdentifier("campaign.reconciliation.problem")
            }
            if let preview { replacementPreview(preview) }
        }
        .onReceive(session.$ledger) { revalidate(in: $0) }
        .onDisappear(perform: discardEditor)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reconcile Citation").font(.headline)
                Spacer()
                Button("Cancel Reconciliation", action: finish)
                    .accessibilityIdentifier("campaign.reconciliation.cancel")
            }
            Text("Compare the retained evidence, choose current lines and a campaign target, then preview the replacement. No lines or targets are mapped automatically.")
                .font(.callout).foregroundStyle(.secondary)
            Text("This records a source link only. It does not carry forward review, approve creative work, authorize spend, or change screenplay or scope text. Existing baselines retain their evidence.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var evidenceComparison: some View {
        HStack(alignment: .top, spacing: 12) {
            oldEvidence.frame(maxWidth: .infinity, alignment: .topLeading)
            currentEvidence.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var oldEvidence: some View {
        GroupBox("Previously cited evidence") {
            VStack(alignment: .leading, spacing: 6) {
                revisionLabel(context.originalRevision)
                Text("Cited lines \(context.citation.firstLine)–\(context.citation.lastLine)").font(.caption.weight(.semibold))
                evidenceText((try? context.originalRevision.excerpt(firstLine: context.citation.firstLine,
                    lastLine: context.citation.lastLine)) ?? "Retained excerpt unavailable.",
                    label: "Previously cited source lines", identifier: "old.excerpt", height: 145)
                Text("Target when cited").font(.caption.weight(.semibold))
                CampaignAgencyTargetEvidenceView(kind: context.citation.targetKind,
                    snapshot: context.citation.targetSnapshot, identifier: "campaign.reconciliation.old.target")
                DisclosureGroup("Previous citation note") {
                    evidenceText(context.citation.note, label: "Previous citation note", identifier: "old.note", height: 65)
                }.font(.caption)
            }.padding(4)
        }
    }

    private var currentEvidence: some View {
        GroupBox("Current evidence to review") {
            VStack(alignment: .leading, spacing: 6) {
                revisionLabel(context.currentRevision)
                Text(context.currentRevision.id == context.citation.revisionID
                     ? "Same source revision; choose lines explicitly."
                     : "New source revision; line positions may have changed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("campaign.reconciliation.sourceStatus")
                evidenceText(context.currentRevision.lines.enumerated().map { "\($0.offset + 1)  \($0.element)" }.joined(separator: "\n"),
                    label: "Current agency source with line numbers", identifier: "current.source", height: 145)
                Text(targetStatus).font(.caption).foregroundStyle(currentOriginalTarget == nil ? .orange : .secondary)
                    .accessibilityIdentifier("campaign.reconciliation.targetStatus")
                if let currentOriginalTarget {
                    CampaignAgencyTargetEvidenceView(kind: context.citation.targetKind,
                        snapshot: currentOriginalTarget, identifier: "campaign.reconciliation.current.target")
                } else {
                    Text("The former target is missing. Choose an existing deliverable or assumption below.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Current source reviewed locally by \(context.review.reviewer)").font(.caption)
                DisclosureGroup("Current source review note") {
                    evidenceText(context.review.note, label: "Current source review note", identifier: "current.review", height: 65)
                }.font(.caption)
            }.padding(4)
        }
    }

    private var targetStatus: String {
        guard let currentOriginalTarget else { return "Previously cited target was removed." }
        return currentOriginalTarget.utf8.elementsEqual(context.citation.targetSnapshot.utf8)
            ? "Previously cited target still matches its retained snapshot."
            : "Previously cited target changed. Compare its fields before choosing."
    }

    private var replacementEditor: some View {
        GroupBox("Choose replacement evidence") {
            VStack(alignment: .leading, spacing: 8) {
                lineRangeEditor
                targetEditor
                if let targetSnapshot {
                    CampaignAgencyTargetEvidenceView(kind: targetKind, snapshot: targetSnapshot,
                                                     identifier: "campaign.reconciliation.selected.target")
                }
                TextField("Explain why these current lines support the selected target", text: edited($note), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    .accessibilityLabel("Reconciliation note")
                    .accessibilityIdentifier("campaign.reconciliation.note")
                Button("Preview Replacement", action: makePreview)
                    .disabled(!canPreview)
                    .accessibilityIdentifier("campaign.reconciliation.preview")
            }.padding(4)
        }
    }

    private var lineRangeEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("First line", text: edited($firstLine)).frame(width: 100)
                    .accessibilityLabel("Replacement first source line")
                    .accessibilityIdentifier("campaign.reconciliation.firstLine")
                Text("through")
                TextField("Last line", text: edited($lastLine)).frame(width: 100)
                    .accessibilityLabel("Replacement last source line")
                    .accessibilityIdentifier("campaign.reconciliation.lastLine")
                Text("of \(context.currentRevision.lines.count)").font(.caption).foregroundStyle(.secondary)
            }
            if let proposedExcerpt {
                evidenceText(proposedExcerpt, label: "Selected replacement source lines", identifier: "selected.excerpt", height: 75)
            } else {
                Text("Enter an inclusive line range from the current source. No range is preselected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if currentOriginalTarget != nil {
                Button("Use Previously Cited Target’s Current State") {
                    selectTarget(kind: context.citation.targetKind, id: context.citation.targetID)
                }.accessibilityIdentifier("campaign.reconciliation.keepTarget")
            }
            Picker("Target type", selection: Binding(get: { targetKind }, set: { kind in
                clearPreview(); targetKind = kind; targetID = nil; targetSnapshot = nil
            })) {
                Text("Deliverable").tag(CampaignAgencyTargetKind.deliverable)
                Text("Assumption").tag(CampaignAgencyTargetKind.assumption)
            }.accessibilityIdentifier("campaign.reconciliation.targetKind")
            Picker("Replacement campaign target", selection: Binding(get: { targetID }, set: { id in
                selectTarget(kind: targetKind, id: id)
            })) {
                Text("Choose target explicitly").tag(Optional<UUID>.none)
                if targetKind == .deliverable {
                    ForEach(session.ledger.draft.deliverables) { value in
                        Text(value.name).tag(Optional(value.id))
                    }
                } else {
                    ForEach(session.ledger.draft.assumptions) { value in
                        Text(value.text).tag(Optional(value.id))
                    }
                }
            }.accessibilityIdentifier("campaign.reconciliation.target")
        }
    }

    private func replacementPreview(_ value: CampaignAgencyCitationReplacementPreview) -> some View {
        GroupBox("Preview: replacement citation") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Replace citation \(value.originalCitation.id.uuidString) with the evidence below in one saved change.")
                    .font(.caption).textSelection(.enabled)
                revisionLabel(value.replacementRevision)
                Text("Lines \(value.firstLine)–\(value.lastLine) · \(value.targetKind.rawValue.capitalized)").font(.callout)
                evidenceText(value.replacementExcerpt, label: "Previewed replacement source lines", identifier: "preview.excerpt", height: 90)
                CampaignAgencyTargetEvidenceView(kind: value.targetKind, snapshot: value.targetSnapshot,
                                                 identifier: "campaign.reconciliation.preview.target")
                evidenceText(value.note, label: "Previewed reconciliation note", identifier: "preview.note", height: 60)
                Text("Only this citation will be replaced. Retained source revisions and historical baselines stay unchanged. Undo Draft Change restores the prior citation.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Confirm Reconciliation") { confirm(value) }
                    .disabled(contextInvalidated || session.isReadOnly)
                    .accessibilityIdentifier("campaign.reconciliation.confirm")
            }.padding(4)
        }.accessibilityIdentifier("campaign.reconciliation.previewEvidence")
    }

    private func revisionLabel(_ value: CampaignAgencyRevision) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.filename).font(.callout.weight(.semibold)).textSelection(.enabled)
            Text("Revision \(value.id.uuidString)\nSHA-256 \(value.sha256)")
                .font(.caption2.monospaced()).textSelection(.enabled)
        }
    }

    private func evidenceText(_ text: String, label: String, identifier: String, height: CGFloat) -> some View {
        CampaignReadOnlyText(text: text, label: label, identifier: "campaign.reconciliation." + identifier)
            .frame(height: height).border(Color.secondary.opacity(0.25))
    }

    private func edited(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { value in
            clearPreview(); binding.wrappedValue = value
        })
    }

    private func clearPreview() { preview = nil; problem = nil }

    private func selectTarget(kind: CampaignAgencyTargetKind, id: UUID?) {
        clearPreview(); targetKind = kind; targetID = id
        targetSnapshot = id.flatMap { try? session.ledger.draft.agencyTargetSnapshot(kind: kind, id: $0) }
    }

    private func makePreview() {
        clearPreview()
        revalidate(in: session.ledger)
        guard canPreview, let first = Int(firstLine), let last = Int(lastLine), let targetID else { return }
        do {
            let value = try session.ledger.draft.previewAgencyCitationReplacement(citationID: context.citation.id,
                revisionID: context.currentRevision.id, firstLine: first, lastLine: last,
                targetKind: targetKind, targetID: targetID, note: note)
            guard let targetSnapshot, value.targetSnapshot.utf8.elementsEqual(targetSnapshot.utf8) else {
                revalidate(in: session.ledger)
                throw CampaignError.invalid("The selected target changed. Choose it again and preview the current evidence.")
            }
            preview = value
        } catch { problem = error.localizedDescription }
    }

    private func confirm(_ value: CampaignAgencyCitationReplacementPreview) {
        guard !contextInvalidated, session.ledger.projectID == context.projectID else { return }
        do { try session.ledger.draft.validateAgencyCitationReplacement(value) }
        catch { preview = nil; problem = error.localizedDescription; return }
        if session.replaceAgencyCitation(value) {
            discardEditor(); finish()
        } else {
            // Storage failures must not discard the explicit proposal or claim
            // success. Domain-stale proposals are revoked rather than refreshed.
            do {
                try session.ledger.draft.validateAgencyCitationReplacement(value)
                problem = (session.problem ?? "The replacement could not be saved.")
                    + " The preview is retained for an explicit retry; nothing was replaced."
            } catch { preview = nil; problem = error.localizedDescription }
        }
    }

    private func revalidate(in ledger: CampaignLedger) {
        guard ledger.projectID == context.projectID,
              let agency = ledger.draft.agency,
              let current = agency.latestRevision(documentID: context.citation.documentID),
              let original = agency.revisions.first(where: { $0.id == context.originalRevision.id }),
              let review = agency.currentReview(revisionID: context.currentRevision.id),
              let citation = agency.citations.first(where: { $0.id == context.citation.id }),
              exactEvidence(current, equals: context.currentRevision),
              exactEvidence(original, equals: context.originalRevision),
              exactEvidence(review, equals: context.review),
              exactEvidence(citation, equals: context.citation) else {
            preview = nil; contextInvalidated = true
            problem = "The source, review, or citation changed. Cancel and reopen reconciliation against current evidence."
            return
        }
        if let targetID, let targetSnapshot {
            let current = try? ledger.draft.agencyTargetSnapshot(kind: targetKind, id: targetID)
            if !(current?.utf8.elementsEqual(targetSnapshot.utf8) ?? false) {
                self.targetID = nil; self.targetSnapshot = nil; preview = nil
                problem = "The selected target changed or was removed. Choose a current target and preview again."
                return
            }
        }
        if let preview {
            do { try ledger.draft.validateAgencyCitationReplacement(preview) }
            catch { self.preview = nil; problem = error.localizedDescription }
        }
    }

    private func exactEvidence<Value: Encodable>(_ lhs: Value, equals rhs: Value) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let lhsBytes = try? encoder.encode(lhs), let rhsBytes = try? encoder.encode(rhs) else { return false }
        return lhsBytes == rhsBytes
    }

    private func discardEditor() {
        firstLine = ""; lastLine = ""; targetKind = .deliverable; targetID = nil
        targetSnapshot = nil; note = ""; preview = nil; problem = nil; contextInvalidated = false
    }
}
