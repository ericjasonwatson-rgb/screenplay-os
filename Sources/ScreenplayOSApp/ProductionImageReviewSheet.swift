import AppKit
import SwiftUI
import ScreenplayDomain

/// Read-only review of a validated, frozen production-image request.
/// Deliberately no Send action: provider payload/consent is a separate gate.
struct ProductionImageReviewSheet: View {
    let review: ProductionImageReferenceReview
    let dismiss: () -> Void

    private var image: NSImage? { NSImage(data: review.imageBytes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Production Image Review").font(.title2.weight(.semibold))
                        Text("Preview only — no image generation or upload is enabled.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close", action: dismiss)
                }
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 320, height: 240)
                            .accessibilityLabel("Approved storyboard reference")
                    } else {
                        Label("Reference image unavailable", systemImage: "exclamationmark.triangle")
                            .frame(width: 320, height: 240)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        detail("Provider", review.providerID)
                        detail("Model", review.modelID)
                        detail("Reference image", "\(review.width) × \(review.height) PNG")
                        detail("Image bytes", String(review.imageSizeBytes))
                        detail("Image SHA-256", review.imageSHA256)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Exact proposed prompt").font(.headline)
                Text(review.prompt)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                detail("Request fingerprint", review.requestSHA256)
                Text(review.costDisclosure)
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text("This screen holds a local preview. It neither authorizes a provider request nor selects a Take. Production generation requires a separate, explicit consent action with a verified image-capable adapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 580)
    }

    private func detail(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}
