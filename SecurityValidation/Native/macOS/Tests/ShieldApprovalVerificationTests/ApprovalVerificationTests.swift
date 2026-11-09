#if os(macOS)
import CryptoKit
import Foundation
import XCTest
import ShieldApprovalContract
@testable import ShieldApprovalVerification

final class ApprovalVerificationTests: XCTestCase {
    private let reviewerID = "reviewer_01"
    private let project = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let request = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private let c = String(repeating: "c", count: 64)

    private func binding(
        projectID: UUID? = nil, requestID: UUID? = nil,
        destination: String = "provider_one", purpose: ApprovalRequestBinding.Purpose = .analyze,
        content: String? = nil, policy: String? = nil, expires: Int64 = 1060
    ) throws -> ApprovalRequestBinding {
        try ApprovalRequestBinding(
            projectID: projectID ?? project, requestID: requestID ?? request,
            agentIdentity: "com.example.agent", destinationID: destination,
            purpose: purpose, contentSHA256: content ?? a,
            policySHA256: policy ?? b, payloadByteCount: 256,
            issuedAtSeconds: 1000, expiresAtSeconds: expires
        )
    }

    private func approval(
        _ key: P256.Signing.PrivateKey,
        _ request: ApprovalRequestBinding,
        keyID: String = "reviewer_01"
    ) throws -> ReviewerApprovalSignature {
        ReviewerApprovalSignature(
            reviewerKeyID: keyID,
            signatureDER: try key.signature(
                for: ReviewerApprovalMessage.bytes(for: request)
            ).derRepresentation
        )
    }

    private func verifier(_ key: P256.Signing.PrivateKey) throws -> EphemeralApprovalVerifier {
        try EphemeralApprovalVerifier(trustedReviewerKeys: [
            reviewerID: key.publicKey.x963Representation
        ])
    }

    func testValidTrustedSignatureAcceptedExactlyOnce() throws {
        let key = P256.Signing.PrivateKey()
        let request = try binding()
        let signed = try approval(key, request)
        let gate = try verifier(key)
        XCTAssertNil(gate.verifyAndConsume(signed, for: request, atTrustedTime: 1005).failure)
        XCTAssertEqual(gate.verifyAndConsume(signed, for: request, atTrustedTime: 1005).failure,
                       .previouslyConsumed)
    }

    func testModifiedContentPolicyDestinationPurposeExpiryOrRequestFails() throws {
        let key = P256.Signing.PrivateKey()
        let original = try binding()
        let signed = try approval(key, original)
        let gate = try verifier(key)
        let changes: [ApprovalRequestBinding] = [
            try binding(content: c),
            try binding(policy: c),
            try binding(destination: "provider_two"),
            try binding(purpose: .publish),
            try binding(expires: 1061),
            try binding(requestID: UUID()),
            try binding(projectID: UUID())
        ]
        for changed in changes {
            XCTAssertEqual(gate.verifyAndConsume(signed, for: changed, atTrustedTime: 1005).failure,
                           .invalidSignature)
        }
        XCTAssertNil(gate.verifyAndConsume(signed, for: original, atTrustedTime: 1005).failure)
    }

    func testUntrustedSignerCannotApprove() throws {
        let trusted = P256.Signing.PrivateKey()
        let attacker = P256.Signing.PrivateKey()
        let request = try binding()
        let gate = try verifier(trusted)
        XCTAssertEqual(gate.verifyAndConsume(try approval(attacker, request),
                                             for: request, atTrustedTime: 1005).failure,
                       .invalidSignature)
    }

    func testUnknownKeyIDRejectedEvenWithValidSignature() throws {
        let trusted = P256.Signing.PrivateKey()
        let request = try binding()
        let signed = try approval(trusted, request, keyID: "attacker")
        XCTAssertEqual(try verifier(trusted).verifyAndConsume(
            signed, for: request, atTrustedTime: 1005
        ).failure, .unknownReviewer)
    }

    func testMalformedSignatureRejectedAndDoesNotConsume() throws {
        let key = P256.Signing.PrivateKey()
        let request = try binding()
        let invalid = ReviewerApprovalSignature(reviewerKeyID: reviewerID, signatureDER: Data([0x00, 0x01]))
        let gate = try verifier(key)
        XCTAssertEqual(gate.verifyAndConsume(invalid, for: request, atTrustedTime: 1005).failure,
                       .invalidSignature)
        XCTAssertNil(gate.verifyAndConsume(try approval(key, request),
                                         for: request, atTrustedTime: 1005).failure)
    }

    func testExpiryAndFutureTimeFailClosed() throws {
        let key = P256.Signing.PrivateKey()
        let request = try binding()
        let signed = try approval(key, request)
        let gate = try verifier(key)
        for t: Int64 in [999, 1060, 2000] {
            XCTAssertEqual(gate.verifyAndConsume(signed, for: request, atTrustedTime: t).failure,
                           .expiredOrNotYetValid)
        }
        XCTAssertNil(gate.verifyAndConsume(signed, for: request, atTrustedTime: 1059).failure)
    }

    func testInvalidTrustConfigurationRejected() throws {
        let key = P256.Signing.PrivateKey()
        XCTAssertThrowsError(try EphemeralApprovalVerifier(trustedReviewerKeys: [:]))
        XCTAssertThrowsError(try EphemeralApprovalVerifier(trustedReviewerKeys: ["BAD id": key.publicKey.x963Representation]))
        XCTAssertThrowsError(try EphemeralApprovalVerifier(trustedReviewerKeys: [reviewerID: Data([0x01, 0x02])]))
    }

    func testDomainSeparatorPreventsSigningBareRequest() throws {
        let key = P256.Signing.PrivateKey()
        let request = try binding()
        let bareSignature = try key.signature(for: request.canonicalBytes)
        let forgery = ReviewerApprovalSignature(reviewerKeyID: reviewerID,
                                                signatureDER: bareSignature.derRepresentation)
        XCTAssertEqual(try verifier(key).verifyAndConsume(
            forgery, for: request, atTrustedTime: 1005
        ).failure, .invalidSignature)
    }

    func testConcurrentConsumptionAllowsOnlyOneWinner() throws {
        let key = P256.Signing.PrivateKey()
        let request = try binding()
        let signed = try approval(key, request)
        let gate = try verifier(key)
        let counter = NSLock()
        var passed = 0
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            if case .success = gate.verifyAndConsume(signed, for: request, atTrustedTime: 1005) {
                counter.lock()
                passed += 1
                counter.unlock()
            }
        }
        XCTAssertEqual(passed, 1)
    }
}

private extension Result where Success == Void, Failure == ApprovalVerificationError {
    var failure: ApprovalVerificationError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
#endif
