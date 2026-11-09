#if os(macOS)
import CryptoKit
import Foundation
import ShieldApprovalContract
import ShieldApprovalVerification

/// Fixed inputs and a public fixture key for the isolated signed XPC exercise.
public enum SignedSample {
    public static let argument = "--signed-local-sample"
    public static let content = "Synthetic studio storyboard notes for local review only."
    public static let policy = "Synthetic policy: local verification only."
    public static let destination = "synthetic.local-only"
    public static let keyID = "signed-xpc-fixture"

    public struct Challenge: Codable {
        public let id: UUID
        public let issuedAt: Int64

        public init() {
            id = UUID()
            issuedAt = SignedSample.now
        }

        public func binding() throws -> ApprovalRequestBinding {
            let (expiry, overflow) = issuedAt.addingReportingOverflow(300)
            guard !overflow else { throw ApprovalRequestBinding.ValidationError.invalidLifetime }
            return try ApprovalRequestBinding(
                projectID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                requestID: id, agentIdentity: "synthetic.fixture",
                destinationID: SignedSample.destination, purpose: .analyze,
                contentSHA256: SignedSample.digest(SignedSample.content),
                policySHA256: SignedSample.digest(SignedSample.policy),
                payloadByteCount: Int64(SignedSample.content.utf8.count),
                issuedAtSeconds: issuedAt, expiresAtSeconds: expiry
            )
        }
    }

    public static var now: Int64 { Int64(Date().timeIntervalSince1970) }

    // Scalar 1 is intentionally public. It is trusted only by this local test.
    public static func fixtureKey() throws -> P256.Signing.PrivateKey {
        try P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 31) + Data([1]))
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#endif
