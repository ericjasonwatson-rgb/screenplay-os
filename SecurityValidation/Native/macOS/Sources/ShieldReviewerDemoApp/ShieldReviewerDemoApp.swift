#if os(macOS)
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI
import ShieldApprovalContract
import ShieldReviewerReview

/// Developer preview ONLY. No XPC, Keychain enrollment, signing or egress.
/// Production requests must arrive via an authenticated trusted helper.
@MainActor
final class ReviewerPreviewModel: ObservableObject {
    @Published var status = "Synthetic demonstration — approvals disabled"
    @Published var authenticated = false
    let preview: ReviewPresentation
    private let session: ReviewerConfirmationSession

    init() {
        let content = Data("Synthetic studio storyboard notes for local review only.".utf8)
        let policy = Data("Synthetic policy: no network, no authorization issued.".utf8)
        func digest(_ value: Data) -> String {
            SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
        }
        let binding = try! ApprovalRequestBinding(
            projectID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            requestID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            agentIdentity: "com.example.agent",
            destinationID: "synthetic.destination",
            purpose: .analyze,
            contentSHA256: digest(content),
            policySHA256: digest(policy),
            payloadByteCount: Int64(content.count),
            issuedAtSeconds: 1000,
            expiresAtSeconds: 1300
        )
        preview = try! ReviewPresentation(binding: binding, contentBytes: content,
                                          effectivePolicyBytes: policy)
        session = ReviewerConfirmationSession(presentation: preview)
    }

    func reject() {
        session.deny()
        authenticated = false
        status = "Rejected locally; no approval or transfer created"
    }

    func demonstrateAuthentication() async {
        guard session.status == .needsReview else { return }
        // The synthetic request uses historical fixed timestamps. The demo
        // intentionally does NOT create a real, time-valid review request.
        // No signing-capable approval process is connected here.
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { context.invalidate() }
        do {
            var possibleError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication,
                                            error: &possibleError) else {
                status = "Local authentication unavailable — nothing approved"
                return
            }
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate this synthetic review demonstration"
            )
            authenticated = ok
            status = ok ? "Authentication demonstrated. Signing and transfer are disabled." :
                          "Authentication denied. No approval created."
        } catch {
            authenticated = false
            status = "Authentication canceled or failed; no approval created"
        }
    }
}

struct ReviewerPreviewWindow: View {
    @StateObject private var model = ReviewerPreviewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Creative IP Shield — Reviewer")
                .font(.title2).bold()
            Text("Validation-only UI. No production signature or AI transfer is possible.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow { Text("Project"); Text(model.preview.binding.projectID.uuidString) }
                GridRow { Text("Agent"); Text(model.preview.binding.agentIdentity) }
                GridRow { Text("Destination"); Text(model.preview.binding.destinationID) }
                GridRow { Text("Purpose"); Text(model.preview.binding.purpose.rawValue) }
                GridRow { Text("Bytes"); Text(String(model.preview.binding.payloadByteCount)) }
                GridRow { Text("Request"); Text(model.preview.binding.requestID.uuidString) }
            }
            Divider()
            Text("Entire synthetic content").bold()
            ScrollView {
                Text(model.preview.completeContent).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 90)
            Text("Effective synthetic policy").bold()
            ScrollView {
                Text(model.preview.effectivePolicy).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 70)
            Text("Request SHA-256: \(model.preview.confirmationDigest)")
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Reject") { model.reject() }
                Button("Test local authentication") {
                    Task { await model.demonstrateAuthentication() }
                }.disabled(model.authenticated)
            }
            Text(model.status).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
    }
}

@main
struct ShieldReviewerDemoApp: App {
    var body: some Scene {
        WindowGroup("Creative IP Shield — Synthetic Reviewer Preview") {
            ReviewerPreviewWindow()
        }
    }
}
#else
import Foundation
@main
struct UnsupportedPlatform { static func main() { exit(78) } }
#endif
