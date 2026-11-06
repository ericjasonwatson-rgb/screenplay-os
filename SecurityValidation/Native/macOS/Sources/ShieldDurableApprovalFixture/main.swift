#if os(macOS)
import CryptoKit
import Foundation
import ShieldApprovalContract
import ShieldApprovalVerification
import ShieldDurableApproval

// CI-ONLY FIXTURE. This executable signs SYNTHETIC requests with ephemeral
// test keys. NEVER use its public-key input as a production trust registry.
// The real macOS helper does not import, run, or depend upon this target.
private struct Fixture: Codable {
    let requestID: String
    let publicKey: Data
    let signatureDER: Data
}

private enum FixtureFailure: Error {
    case usage
    case malformedRequest
    case unexpectedClaim(String)
}

private func request(for requestID: String) throws -> ApprovalRequestBinding {
    guard let uuid = UUID(uuidString: requestID) else { throw FixtureFailure.malformedRequest }
    return try ApprovalRequestBinding(
        projectID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        requestID: uuid,
        agentIdentity: "com.example.agent",
        destinationID: "provider_one",
        purpose: .analyze,
        contentSHA256: String(repeating: "a", count: 64),
        policySHA256: String(repeating: "b", count: 64),
        payloadByteCount: 256,
        issuedAtSeconds: 1000,
        expiresAtSeconds: 1060
    )
}

private func execute() throws {
    let args = CommandLine.arguments
    guard args.count >= 3 else { throw FixtureFailure.usage }
    switch args[1] {
    case "sign":
        guard args.count == 3 else { throw FixtureFailure.usage }
        let expected = try request(for: args[2])
        let privateKey = P256.Signing.PrivateKey()
        let fixture = Fixture(
            requestID: args[2],
            publicKey: privateKey.publicKey.x963Representation,
            signatureDER: try privateKey.signature(
                for: ReviewerApprovalMessage.bytes(for: expected)
            ).derRepresentation
        )
        let json = try JSONEncoder().encode(fixture)
        print(String(decoding: json, as: UTF8.self))
    case "state":
        guard args.count == 3 else { throw FixtureFailure.usage }
        let tempKey = P256.Signing.PrivateKey()
        let verifier = try EphemeralApprovalVerifier(trustedReviewerKeys: [
            "fixture_only": tempKey.publicKey.x963Representation
        ])
        let ledger = try DurableApprovalClaimLedger(
            databaseURL: URL(fileURLWithPath: args[2]), verifier: verifier
        )
        print(String(decoding: try JSONEncoder().encode(ledger.stateCommitment()), as: UTF8.self))
    case "compare":
        guard args.count == 4 else { throw FixtureFailure.usage }
        let tempKey = P256.Signing.PrivateKey()
        let verifier = try EphemeralApprovalVerifier(trustedReviewerKeys: [
            "fixture_only": tempKey.publicKey.x963Representation
        ])
        let ledger = try DurableApprovalClaimLedger(
            databaseURL: URL(fileURLWithPath: args[2]), verifier: verifier
        )
        let expected = try JSONDecoder().decode(
            LedgerStateCommitment.self,
            from: Data(contentsOf: URL(fileURLWithPath: args[3]))
        )
        if ledger.matchesTrustedCheckpoint(expected) {
            print("MATCH")
        } else {
            print("ROLLBACK_OR_MISMATCH")
            exit(43)
        }
    case "bootstrap":
        guard args.count == 3 else { throw FixtureFailure.usage }
        try DurableApprovalClaimLedger.bootstrap(at: URL(fileURLWithPath: args[2]))
        print("BOOTSTRAPPED")
    case "claim":
        guard args.count == 4 else { throw FixtureFailure.usage }
        let url = URL(fileURLWithPath: args[2])
        let fixture = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: args[3]))
        )
        let expected = try request(for: fixture.requestID)
        let verifier = try EphemeralApprovalVerifier(trustedReviewerKeys: [
            "reviewer_01": fixture.publicKey
        ])
        let registry = try DurableApprovalClaimLedger(databaseURL: url, verifier: verifier)
        let signature = ReviewerApprovalSignature(
            reviewerKeyID: "reviewer_01", signatureDER: fixture.signatureDER
        )
        switch registry.claim(signature, for: expected, atTrustedTime: 1005) {
        case .success: print("CLAIMED")
        case .failure(.previouslyClaimed): print("DUPLICATE"); exit(42)
        case .failure: print("DENIED"); exit(42)
        }
    default:
        throw FixtureFailure.usage
    }
}

// SwiftPM treats main.swift as the executable entrypoint without @main.
do {
    try execute()
} catch {
    // Never emit secrets or paths in the CI failure path.
    fputs("DENIED\n", stderr)
    exit(42)
}
#else
import Foundation
exit(78)
#endif
