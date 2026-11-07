#if os(macOS)
import Foundation
import SwiftUI
import ShieldNativeContract
import ShieldReviewerKeychain

/// Validation-only, signing-library-linked candidate. No live review inbox,
/// Secure Enclave enrollment UI, signature action, XPC requests, or egress.
@MainActor
private enum ReviewerCandidatePreflight {
    static func requireSignedReviewer() {
        func bundled(_ key: String) -> String {
            guard let value = Bundle.main.object(
                forInfoDictionaryKey: key
            ) as? String, !value.isEmpty else {
                fputs("reviewer missing signed deployment configuration\n", stderr)
                exit(78)
            }
            return value
        }
        do {
            let config = try SignedPeerConfiguration(
                teamID: bundled("CIPSTeamID"),
                agentBundleID: bundled("CIPSAgentBundleID"),
                reviewerBundleID: bundled("CFBundleIdentifier"),
                helperBundleID: bundled("CIPSHelperBundleID"),
                agentMachService: bundled("CIPSAgentMachService"),
                reviewerMachService: bundled("CIPSReviewerMachService")
            )
            guard config.reviewerBundleID == bundled("CIPSReviewerBundleID"),
                  Bundle.main.object(
                    forInfoDictionaryKey: "CIPSValidationOnly"
                  ) as? Bool == true,
                  Bundle.main.object(
                    forInfoDictionaryKey: "CIPSNoRealApprovalOrEgress"
                  ) as? Bool == true,
                  Bundle.main.object(
                    forInfoDictionaryKey: "CIPSReviewerCandidate"
                  ) as? Bool == true,
                  ReviewerKeyStore(configuration: config).isAuthorizedRunningReviewer() else {
                fputs("reviewer signing identity not trusted; startup refused\n", stderr)
                exit(78)
            }
        } catch {
            fputs("reviewer deployment configuration refused\n", stderr)
            exit(78)
        }
    }
}

@main
private struct ShieldReviewerCandidateApp: App {
    init() {
        // Refuse before displaying even a demonstration window.
        ReviewerCandidatePreflight.requireSignedReviewer()
    }

    var body: some Scene {
        WindowGroup("Creative IP Shield — Signing Candidate") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Creative IP Shield").font(.title).bold()
                Text("Developer ID signing acceptance candidate")
                    .font(.title3)
                Text("The code-signing preflight passed, but approval and transfers are disabled.")
                Divider()
                Text("No connected review inbox")
                Text("No key enrollment or signing action")
                Text("No provider connection or content transfer")
                Text("No trusted checkpoint authority")
                Text("Only synthetic tests are supported.")
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(minWidth: 600, minHeight: 340)
        }
    }
}
#else
import Foundation
exit(78)
#endif
