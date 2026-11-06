import SwiftUI

/// Inline review keeps recovery inside the existing Campaign presentation.
/// Cancellation never creates a second sheet or replaces local history.
@MainActor
struct CampaignBackupReviewView: View {
    let preview: CampaignBackupRestorePreview
    let isRestoring: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        GroupBox("Review campaign backup before restoring") {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(preview.filename) · \(preview.byteCount) bytes")
                    .font(.callout.weight(.semibold)).textSelection(.enabled)
                    .accessibilityIdentifier("campaign.backup.filename")
                Text(verbatim: "Project ID: \(preview.projectID.uuidString)")
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("campaign.backup.project")
                Text("\(preview.deliverableCount) deliverables · \(preview.assumptionCount) assumptions · \(preview.baselineCount) baselines · \(preview.decisionCount) decisions")
                    .font(.caption)
                    .accessibilityIdentifier("campaign.backup.history")
                Text("\(preview.agencyDocumentCount) source documents · \(preview.agencyRevisionCount) source revisions · \(preview.retainedOriginalCount) retained originals")
                    .font(.caption)
                    .accessibilityIdentifier("campaign.backup.sources")
                Text(preview.disclosure)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("campaign.backup.disclosure")
                HStack {
                    Button("Cancel Restore", action: cancel)
                        .accessibilityIdentifier("campaign.backup.cancel")
                    Spacer()
                    Button("Restore Reviewed Backup", action: confirm)
                        .disabled(isRestoring)
                        .accessibilityIdentifier("campaign.backup.confirm")
                }
            }.padding(6)
        }
    }
}
