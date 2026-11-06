import SwiftUI
import ScreenplayDomain

/// One transient review entry. Its baseline identity and parent presentation gate
/// are checked again when the native destination chooser returns.
@MainActor
struct CampaignChangeReviewView: View {
    @ObservedObject var session: CampaignWorkspaceSession
    @ObservedObject var model: ScreenplayViewModel
    let baseline: CampaignBaseline
    var exportLifecycle: CampaignReportExportLifecycle?
    let isContextActive: () -> Bool
    @State private var includeFullEvidence = false
    @State private var preview: CampaignChangeReportPreview?
    @State private var problem: String?
    @State private var retired = false

    private var document: ScreenplayOSDocument? {
        guard model.document?.project.id == session.ledger.projectID else { return nil }
        return model.document
    }

    var body: some View {
        GroupBox("Review a local change report") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary is the default. It includes user-entered project and baseline titles, deliverable names and identifiers that may be confidential. It is not redacted or automatically safe to share.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Include full before / after evidence", isOn: Binding(
                    get: { includeFullEvidence },
                    set: { value in
                        guard value != includeFullEvidence else { return }
                        clearPreview()
                        includeFullEvidence = value
                    }))
                    .accessibilityIdentifier("campaign.report.includeFullEvidence")
                Text("Full evidence can include complete imported agency text and script content, including confidential material. Inspect the entire report before saving or sharing.")
                    .font(.caption).foregroundStyle(includeFullEvidence ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("campaign.report.evidenceWarning")
                Text("Saving creates a local copy only. Nothing is sent to anyone. This report does not calculate costs, record approval, or authorize spending.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Preview Change Review", action: makePreview)
                        .disabled(document == nil || session.isReadOnly || retired)
                        .accessibilityIdentifier("campaign.report.preview")
                    Button("Cancel", action: cancelEntry)
                        .accessibilityIdentifier("campaign.report.cancel")
                }
                if let problem {
                    Text(verbatim: problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                        .accessibilityIdentifier("campaign.report.problem")
                }
                if let preview {
                    Text(verbatim: preview.options.includeFullEvidence ? "Full evidence preview" : "Summary preview")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("campaign.report.mode")
                    CampaignReadOnlyText(text: preview.text, label: "Exact change report to save",
                                         identifier: "campaign.report.text")
                        .frame(height: 240).border(Color.secondary.opacity(0.25))
                    Button("Save Reviewed Copy…") { save(preview) }
                        .disabled(document == nil || session.isReadOnly || retired)
                        .accessibilityIdentifier("campaign.report.save")
                }
            }.padding(6)
        }
        // @Published delivers before storage changes. Validate against the incoming
        // value so an edit cannot leave a now-obsolete preview visible.
        .onReceive(session.$ledger) { ledger in revalidate(ledger: ledger, document: model.document) }
        .onReceive(model.$document) { document in revalidate(ledger: session.ledger, document: document) }
        .onDisappear {
            retired = true
            cancelEntry()
        }
    }

    private func makePreview() {
        clearPreview()
        guard !retired, isContextActive(), let document else { return }
        preview = session.previewReport(baselineID: baseline.id, document: document,
                                        includeFullEvidence: includeFullEvidence)
    }

    private func save(_ value: CampaignChangeReportPreview) {
        guard !retired, isContextActive(), preview?.id == value.id else { return }
        revalidate(ledger: session.ledger, document: document)
        guard preview?.id == value.id else { return }
        let saved = session.saveReviewedReport(value, lifecycle: exportLifecycle ?? .live, currentContext: {
            guard !retired, isContextActive(), preview?.id == value.id,
                  includeFullEvidence == value.options.includeFullEvidence,
                  let document else { return nil }
            return (baselineID: baseline.id, document: document, sourceURL: model.saveURL)
        })
        if saved {
            cancelEntry()
        } else {
            revalidate(ledger: session.ledger, document: document)
        }
    }

    private func revalidate(ledger: CampaignLedger, document: ScreenplayOSDocument?) {
        guard let preview else { return }
        guard !retired, isContextActive(), let document, preview.baselineID == baseline.id,
              (try? preview.contextMatches(ledger: ledger, document: document)) == true else {
            clearPreview()
            problem = "The campaign or its sources changed. Preview the current report again before saving."
            return
        }
    }

    private func clearPreview() {
        preview = nil
        problem = nil
        if session.reportPreview != nil { session.discardReportPreview() }
    }

    private func cancelEntry() {
        clearPreview()
        includeFullEvidence = false
    }
}
