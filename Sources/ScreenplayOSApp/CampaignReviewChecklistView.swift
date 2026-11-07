import SwiftUI
import ScreenplayDomain

/// A transient guide into the existing panel, not a completion score or a new
/// authority to import evidence, freeze scope, record decisions or export files.
@MainActor
struct CampaignReviewChecklistView: View {
    let checklist: CampaignReviewChecklist
    let navigate: (CampaignReviewDestination) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next review step").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: checklist.nextStep.title).font(.callout.weight(.semibold))
                    Text(verbatim: checklist.nextStep.summary)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("campaign.review.summary")
                }
                Spacer(minLength: 8)
                Button("Go to Step") { navigate(checklist.nextStep.destination) }
                    .accessibilityLabel("Go to next review step: \(checklist.nextStep.title)")
                    .accessibilityIdentifier("campaign.review.nextStep")
            }
            Button {
                expanded.toggle()
            } label: {
                Label(expanded ? "Hide review checklist" : "Show review checklist",
                      systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("campaign.review.details")
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(checklist.items) { item in
                            checklistRow(item)
                        }
                        Text("Review guide only. Human review is still required; this does not establish exhaustive coverage, approval or spending authority.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func checklistRow(_ item: CampaignReviewChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.needsAttention ? "exclamationmark.circle" : "circle")
                .foregroundStyle(item.needsAttention ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.title).font(.caption.weight(.semibold))
                Text(verbatim: item.summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("campaign.review.row.\(item.id).summary")
                if !item.details.isEmpty {
                    Text(verbatim: item.details.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("campaign.review.row.\(item.id).details")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open") { navigate(item.destination) }
                .accessibilityLabel("Open \(item.title)")
                .accessibilityIdentifier("campaign.review.row.\(item.id)")
        }
    }
}
