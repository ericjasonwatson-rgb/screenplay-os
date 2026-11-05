import AppKit
import SwiftUI
import ScreenplayDomain

/// An explicit, separate review of one immutable job and its approved image.
/// The action grants durable consent only; there is intentionally no network
/// Send action in this sheet or the caller that presents it.
struct ProductionImageConsentDecisionSheet: View {
    let consent: GenerationConsentPreview
    let imageReview: ProductionImageReferenceReview
    let approveForQueue: () -> Void
    let dismiss: () -> Void

    @State private var acknowledgeExternalTransfer = false

    private var matches: Bool {
        consent.capability == .image &&
        consent.jobID == imageReview.jobID &&
        consent.requestSHA256 == imageReview.requestSHA256 &&
        consent.providerID == imageReview.providerID &&
        consent.modelID == imageReview.modelID &&
        consent.request.prompt == imageReview.prompt &&
        consent.request.references.count == 1 &&
        consent.request.references[0].sha256 == imageReview.imageSHA256
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Review External Image Request").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Close", action: dismiss)
                }
                Text("This is a separate authorization from storyboard approval. The request remains on this Mac until a later, explicit Send action is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
                if let image = NSImage(data: imageReview.imageBytes) {
                    Image(nsImage: image)
                        .resizable().scaledToFit().frame(maxHeight: 260)
                        .accessibilityLabel("Exact storyboard reference proposed for external transfer")
                }
                row("Provider", consent.providerID)
                row("Model", consent.modelID)
                row("Reference image", "\(imageReview.width) × \(imageReview.height) PNG (\(imageReview.imageSizeBytes) bytes)")
                row("Image SHA-256", imageReview.imageSHA256)
                row("Request SHA-256", consent.requestSHA256)
                Text("Exact proposed prompt").font(.headline)
                Text(consent.request.prompt)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                Text(imageReview.costDisclosure).foregroundStyle(.orange).font(.callout)
                Toggle(
                    "I reviewed the exact image, prompt and provider, and understand that a later Send action would transmit this material externally and may incur API charges.",
                    isOn: $acknowledgeExternalTransfer
                )
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Authorize locally — queue only, no send", action: approveForQueue)
                        .disabled(!acknowledgeExternalTransfer || !matches)
                    Button("Not now", action: dismiss)
                }
                if !matches {
                    Label("The saved job and reference no longer match. Close this review and stage a new request.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 660, idealWidth: 800, minHeight: 600)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}
