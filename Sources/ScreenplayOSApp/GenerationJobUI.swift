import AppKit
import CryptoKit
import ScreenplayDomain
import SwiftUI

struct GenerationConsentSheet: View {
    let preview: GenerationConsentPreview
    let send: () -> Void
    let cancel: () -> Void

    private var costText: String {
        guard let cost = preview.estimatedCost else { return "Unavailable" }
        return "\(cost.currency) \(String(format: "%.6f", Double(cost.amountMicros) / 1_000_000))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review AI request").font(.title2.weight(.semibold))
            Text("Nothing is sent until you approve this exact request.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                GridRow { Text("Provider").foregroundStyle(.secondary); Text(preview.providerID) }
                GridRow { Text("Model").foregroundStyle(.secondary); Text(preview.modelID) }
                GridRow { Text("Capability").foregroundStyle(.secondary); Text(preview.capability.rawValue.capitalized) }
                GridRow { Text("Target").foregroundStyle(.secondary); Text("\(preview.target.kind.rawValue) · \(preview.target.id.uuidString)") }
                GridRow { Text("Estimated cost").foregroundStyle(.secondary); Text(costText) }
            }
            Text("Exact prompt").font(.headline)
            ScrollView {
                Text(preview.request.prompt)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 180)
            .background(StudioAppearance.recess, in: RoundedRectangle(cornerRadius: 6))
            if !preview.request.references.isEmpty {
                Text("References: \(preview.request.references.map(\.relativePath).joined(separator: ", "))")
                    .font(.caption).textSelection(.enabled)
            }
            if !preview.request.parameters.isEmpty {
                Text(preview.request.parameters.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Offline fixture: no screenplay content or credentials leave this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                Spacer()
                Button("Send to Offline Fixture", action: send)
                    .buttonStyle(StudioButtonStyle(ai: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 500)
        .interactiveDismissDisabled()
    }
}

enum OfflineGenerationWorkflow {
    static func sourceRevision(_ snapshot: DialogueSnapshot) -> String {
        let source = snapshot.elements.map { "\($0.id.uuidString)\u{1f}\($0.type.rawValue)\u{1f}\($0.text)" }
            .joined(separator: "\u{1e}")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func storageURL(projectID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
        return base.appendingPathComponent("ScreenplayOS/AIJobs/\(projectID.uuidString)/generation-jobs-v1.json")
    }
}
