import AppKit
import SwiftUI
import ScreenplayDomain

/// Transient entry bound to one baseline identity, never part of the saved draft.
@MainActor
struct CampaignApprovalReviewView: View {
    @ObservedObject var session: CampaignWorkspaceSession
    @ObservedObject var model: ScreenplayViewModel
    let baseline: CampaignBaseline
    let current: Bool
    @State private var scope: CampaignApprovalScope = .creative
    // String equality treats composed and decomposed Unicode as equal. Keep
    // exact bytes in transient state so every distinct native edit is retained.
    @State private var approverBytes = Data()
    @State private var evidenceBytes = Data()
    @State private var ceilingBytes = Data()
    @State private var currencyBytes = Data("USD".utf8)
    @State private var preview: CampaignDecisionPreview?
    @State private var problem: String?

    private var approver: String { String(decoding: approverBytes, as: UTF8.self) }
    private var evidence: String { String(decoding: evidenceBytes, as: UTF8.self) }
    private var ceiling: String { String(decoding: ceilingBytes, as: UTF8.self) }
    private var currency: String { String(decoding: currencyBytes, as: UTF8.self) }

    private var document: ScreenplayOSDocument? {
        guard model.document?.project.id == session.ledger.projectID else { return nil }
        return model.document
    }
    private var canPreview: Bool {
        current && document != nil && !session.isReadOnly
            && !approver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GroupBox("Record an approval already received") {
            VStack(alignment: .leading, spacing: 8) {
                baselineLabel(baseline, prefix: "baseline")
                Text("Local evidence only, not identity verification or an electronic signature. This record does not authorize spend, a payment, or a provider request. Creative approval never authorizes spend.")
                    .font(.caption).foregroundStyle(.secondary)
                if !current {
                    Text("This baseline no longer matches current sources. Review the changes and freeze a new baseline before recording approval.")
                        .font(.caption).foregroundStyle(.orange)
                }
                entryFields
                HStack {
                    Button("Preview Local Record", action: makePreview)
                        .disabled(!canPreview)
                        .accessibilityIdentifier("campaign.approval.preview")
                    Button("Cancel Entry", action: discardEntry)
                        .accessibilityIdentifier("campaign.approval.cancel")
                }
                if let problem {
                    Text(problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        .accessibilityIdentifier("campaign.approval.problem")
                }
                if let preview { previewEvidence(preview) }
            }.padding(6)
        }
        // Use the publisher's incoming value: @Published fires before storage changes.
        .onReceive(session.$ledger) { ledger in revalidate(ledger: ledger, document: model.document) }
        .onReceive(model.$document) { document in revalidate(ledger: session.ledger, document: document) }
        .onDisappear(perform: discardEntry)
    }

    private var entryFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Scope", selection: Binding(get: { scope }, set: { value in
                guard value != scope else { return }
                clearPreview(); scope = value; clearFields()
            })) {
                Text("Creative").tag(CampaignApprovalScope.creative)
                Text("Production approach").tag(CampaignApprovalScope.production)
                Text("Additional spend").tag(CampaignApprovalScope.spend)
            }.pickerStyle(.segmented).accessibilityIdentifier("campaign.approval.scope")
            field("Approved by", bytes: $approverBytes, identifier: "approver")
            field("Evidence / message reference", bytes: $evidenceBytes, identifier: "evidence")
            if scope == .spend {
                HStack {
                    field("Ceiling in minor units", bytes: $ceilingBytes, identifier: "ceiling")
                    field("Currency", bytes: $currencyBytes, identifier: "currency")
                }
                Text("For USD 125.00, enter 12500 and USD. The ceiling records evidence only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(!current || session.isReadOnly || document == nil)
    }

    private func baselineLabel(_ value: CampaignBaseline, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.name).font(.callout.weight(.semibold)).textSelection(.enabled)
                .accessibilityIdentifier("campaign.approval.\(prefix).name")
            Text("Baseline UUID: \(value.id.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                .accessibilityIdentifier("campaign.approval.\(prefix).id")
            Text("Frozen: \(value.createdAt.formatted(date: .complete, time: .complete))")
                .font(.caption).textSelection(.enabled)
                .accessibilityIdentifier("campaign.approval.\(prefix).date")
        }
    }

    private func previewEvidence(_ value: CampaignDecisionPreview) -> some View {
        GroupBox("Review before recording locally") {
            VStack(alignment: .leading, spacing: 8) {
                baselineLabel(value.baseline, prefix: "preview.baseline")
                Text("Scope: \(value.decision.scope.rawValue.capitalized)")
                    .accessibilityIdentifier("campaign.approval.preview.scope")
                CampaignReadOnlyText(text: value.decision.approver, label: "Previewed approved by",
                                     identifier: "campaign.approval.preview.approver")
                    .frame(height: 45)
                CampaignReadOnlyText(text: value.decision.evidence, label: "Previewed approval evidence",
                                     identifier: "campaign.approval.preview.evidence")
                    .frame(height: 90)
                if let amount = value.decision.spendCeilingMinorUnits, let code = value.decision.currencyCode {
                    Text("Ceiling: \(amount) minor units · \(code)")
                        .accessibilityIdentifier("campaign.approval.preview.ceiling")
                }
                Text("This immutable record stays attached to this baseline. Undo Draft Change does not erase recorded decisions. Nothing is sent to anyone.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The record time is assigned when you confirm.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Confirm Local Record") { confirm(value) }
                    .disabled(!current || session.isReadOnly || document == nil)
                    .accessibilityIdentifier("campaign.approval.confirm")
            }.padding(4)
        }.accessibilityIdentifier("campaign.approval.previewEvidence")
    }

    private func field(_ label: String, bytes: Binding<Data>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            CampaignApprovalTextField(bytes: Binding(get: { bytes.wrappedValue }, set: { value in
                if bytes.wrappedValue != value { clearPreview() }
                bytes.wrappedValue = value
            }), label: label, identifier: "campaign.approval." + identifier)
                .frame(maxWidth: .infinity)
        }
    }

    private func clearFields() {
        approverBytes = Data(); evidenceBytes = Data(); ceilingBytes = Data()
        currencyBytes = Data("USD".utf8)
    }

    private func makePreview() {
        clearPreview()
        guard canPreview, let document else { return }
        preview = session.previewDecision(baselineID: baseline.id, scope: scope, approver: approver,
            evidence: evidence, document: document, amount: ceiling, currency: currency)
    }

    private func confirm(_ value: CampaignDecisionPreview) {
        guard let document, preview?.id == value.id else { return }
        revalidate(ledger: session.ledger, document: document)
        guard preview?.id == value.id else { return }
        if session.confirmDecision(value, baselineID: baseline.id, document: document) {
            discardEntry()
        } else {
            revalidate(ledger: session.ledger, document: document)
            if preview != nil {
                problem = (session.problem ?? "The record could not be saved.")
                    + " Nothing was recorded. The exact preview is retained for an explicit retry."
            }
        }
    }

    private func revalidate(ledger: CampaignLedger, document: ScreenplayOSDocument?) {
        guard let preview else { return }
        guard let document, preview.baseline.id == baseline.id,
              (try? preview.contextMatches(ledger: ledger, document: document)) == true else {
            clearPreview()
            problem = "The campaign or its sources changed. Review the current baseline and preview again."
            return
        }
    }

    private func clearPreview() {
        preview = nil; problem = nil; session.discardDecisionPreview()
    }

    private func discardEntry() {
        clearPreview(); scope = .creative; clearFields()
    }
}

/// SwiftUI TextField can coalesce canonically equivalent Unicode before calling
/// its binding setter. Capture native editing notifications and store UTF-8 bytes
/// directly instead; this is local approval entry only, not a screenplay editor.
private struct CampaignApprovalTextField: NSViewRepresentable {
    @Binding var bytes: Data
    let label: String
    let identifier: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.maximumNumberOfLines = 4
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.placeholderString = label
        field.setAccessibilityLabel(label)
        field.setAccessibilityIdentifier(identifier)
        let text = String(decoding: bytes, as: UTF8.self)
        // Never replace a matching field editor's string or marked-text state.
        let displayed = field.currentEditor()?.string ?? field.stringValue
        if !displayed.utf8.elementsEqual(text.utf8) {
            field.stringValue = text
            if let editor = field.currentEditor(), !editor.string.utf8.elementsEqual(text.utf8) {
                editor.string = text
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let measured = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 80))
        return CGSize(width: width, height: min(80, max(24, measured?.height ?? 24)))
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.isActive = false
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CampaignApprovalTextField
        var isActive = true
        init(_ parent: CampaignApprovalTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) { capture(notification) }
        func controlTextDidEndEditing(_ notification: Notification) { capture(notification) }

        private func capture(_ notification: Notification) {
            guard isActive, let field = notification.object as? NSTextField else { return }
            let text = field.currentEditor()?.string ?? field.stringValue
            let exactBytes = Data(text.utf8)
            if parent.bytes != exactBytes { parent.bytes = exactBytes }
        }
    }
}
