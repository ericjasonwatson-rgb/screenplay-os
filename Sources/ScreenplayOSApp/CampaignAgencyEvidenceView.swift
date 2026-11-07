import AppKit
import SwiftUI
import ScreenplayDomain

/// Native, selectable plain text with a bounded viewport. The exact UTF-8
/// comparison avoids treating canonically equivalent Unicode as unchanged.
struct CampaignReadOnlyText: NSViewRepresentable {
    let text: String
    var label = "Imported agency source text"
    var identifier = "campaign.agency.sourceText"

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false; view.isSelectable = true; view.isRichText = false
            view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            view.textContainerInset = NSSize(width: 6, height: 6)
        }
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let editor = view.documentView as? NSTextView else { return }
        editor.setAccessibilityLabel(label)
        editor.setAccessibilityIdentifier(identifier)
        if !editor.string.utf8.elementsEqual(text.utf8) { editor.string = text }
    }
}

struct CampaignAgencyTargetEvidenceView: View {
    let kind: CampaignAgencyTargetKind
    let snapshot: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CampaignReadOnlyText(text: readableEvidence, label: "Campaign target evidence", identifier: identifier)
                .frame(height: 112).border(Color.secondary.opacity(0.25))
            DisclosureGroup("Exact retained target snapshot") {
                CampaignReadOnlyText(text: snapshot, label: "Exact campaign target snapshot", identifier: identifier + ".snapshot")
                    .frame(height: 80).border(Color.secondary.opacity(0.25))
            }.font(.caption)
        }
    }

    private var readableEvidence: String {
        let data = Data(snapshot.utf8)
        switch kind {
        case .deliverable:
            guard let value = try? JSONDecoder().decode(CampaignDeliverable.self, from: data) else {
                return "Target evidence could not be displayed. Check its exact retained snapshot."
            }
            return """
            Deliverable: \(value.name)
            Duration: \(value.durationSeconds) seconds
            Aspect ratio: \(value.aspectRatio)
            Market: \(value.market)
            Language: \(value.language)
            Target ID: \(value.id.uuidString)
            Linked shot IDs: \(value.linkedShotIDs.map(\.uuidString).joined(separator: ", "))
            """
        case .assumption:
            guard let value = try? JSONDecoder().decode(CampaignAssumption.self, from: data) else {
                return "Target evidence could not be displayed. Check its exact retained snapshot."
            }
            return """
            Assumption: \(value.text)
            Source document / version: \(value.sourceLabel)
            Page / section / reference: \(value.sourceReference)
            Target ID: \(value.id.uuidString)
            """
        }
    }
}
