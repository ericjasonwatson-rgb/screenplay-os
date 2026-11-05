import AppKit
import SwiftUI
import ScreenplayDomain

/// Final user action required before uploading creative IP to OpenAI.
/// The explicit button is only displayed for a locally queued, immutable job.
/// Nothing is sent on display, onChange, task, or appearance.
struct ProductionImageSendConfirmationSheet: View {
    let consent: GenerationConsentPreview
    let reference: ProductionImageReferenceReview
    let confirmSend: () -> Void
    let dismiss: () -> Void

    @State private var acknowledged = false

    private var current: Bool {
        consent.jobID == reference.jobID &&
        consent.requestSHA256 == reference.requestSHA256 &&
        consent.providerID == reference.providerID &&
        consent.modelID == reference.modelID &&
        consent.request.prompt == reference.prompt &&
        consent.request.references.count == 1 &&
        consent.request.references[0].sha256 == reference.imageSHA256 &&
        consent.capability == .image
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Send Production Image to OpenAI").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Not now", action: dismiss)
                }
                Text("This sends the reviewed storyboard PNG and the exact instructions to OpenAI. Image API charges may apply. The result will be saved as a candidate Take, not selected automatically.")
                    .font(.callout)
                if let image = NSImage(data: reference.imageBytes) {
                    Image(nsImage: image)
                        .resizable().scaledToFit().frame(maxHeight: 230)
                        .accessibilityLabel("Exact image to send externally")
                }
                Text("Provider: \(consent.providerID) · Model: \(consent.modelID)")
                    .font(.subheadline.weight(.semibold))
                Text("Image SHA-256: \(reference.imageSHA256)")
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("Request SHA-256: \(consent.requestSHA256)")
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("Exact outgoing prompt").font(.headline)
                Text(consent.request.prompt)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                Text(reference.costDisclosure).foregroundStyle(.orange)
                Toggle(
                    "I authorize sending this specific image and prompt to OpenAI now, understand that API charges may apply, and want the result as an unselected Take.",
                    isOn: $acknowledged
                )
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Send now (may incur charges)", action: confirmSend)
                        .disabled(!acknowledged || !current)
                    Button("Cancel", action: dismiss)
                }
                if !current {
                    Label("Request and reference no longer match; do not send.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 680, idealWidth: 800, minHeight: 650)
    }
}
