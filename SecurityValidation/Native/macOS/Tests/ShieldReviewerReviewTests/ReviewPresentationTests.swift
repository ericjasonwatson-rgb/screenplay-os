#if os(macOS)
import CryptoKit
import Foundation
import XCTest
import ShieldApprovalContract
@testable import ShieldReviewerReview

final class ReviewerReviewTests: XCTestCase {
    private let payload = Data("Synthetic screenplay excerpt.\nNo real project content.".utf8)
    private let policy = Data("Synthetic policy: preview-only, no external transfer.".utf8)
    private func hex(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
    private func make(
        payload: Data? = nil, policy: Data? = nil,
        bindingPayload: Data? = nil, bindingPolicy: Data? = nil,
        issuedAt: Int64 = 1000, expiresAt: Int64 = 1040
    ) throws -> ReviewPresentation {
        let p = payload ?? self.payload
        let pol = policy ?? self.policy
        let authoritativeContent = bindingPayload ?? self.payload
        let authoritativePolicy = bindingPolicy ?? self.policy
        let request = try ApprovalRequestBinding(
            projectID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            requestID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            agentIdentity: "com.example.agent", destinationID: "approved.provider",
            purpose: .analyze, contentSHA256: hex(authoritativeContent),
            policySHA256: hex(authoritativePolicy),
            payloadByteCount: Int64(authoritativeContent.count),
            issuedAtSeconds: issuedAt, expiresAtSeconds: expiresAt
        )
        return try ReviewPresentation(binding: request, contentBytes: p,
                                      effectivePolicyBytes: pol)
    }

    func testExactFullTextSnapshot() throws {
        let snapshot = try make()
        XCTAssertEqual(snapshot.completeContent, String(decoding: payload, as: UTF8.self))
        XCTAssertEqual(snapshot.effectivePolicy, String(decoding: policy, as: UTF8.self))
        XCTAssertEqual(snapshot.confirmationDigest.count, 64)
    }
    func testChangedPayloadRefusedBeforeDisplay() throws {
        XCTAssertThrowsError(try make(payload: Data("altered".utf8))) {
            XCTAssertEqual($0 as? ReviewPreviewError, .contentMismatch)
        }
    }
    func testChangedPolicyRefusedBeforeDisplay() throws {
        XCTAssertThrowsError(try make(policy: Data("allow all".utf8))) {
            XCTAssertEqual($0 as? ReviewPreviewError, .policyMismatch)
        }
    }
    func testBinaryBidiControlsAndOversizeCannotBeReviewed() throws {
        for bytes in [Data([0xff, 0xfe]), Data("hidden\u{202E}text".utf8),
                      Data(repeating: 65, count: 16_385)] {
            XCTAssertThrowsError(try make(payload: bytes, bindingPayload: bytes))
        }
    }
    func testConfirmationRequiresExactDigestAndTrustedTime() throws {
        let snapshot = try make()
        let flow = ReviewerConfirmationSession(presentation: snapshot)
        XCTAssertNil(flow.consumeConfirmed(trustedNowSeconds: 1001))
        XCTAssertFalse(flow.explicitlyConfirm(digest: "wrong", trustedNowSeconds: 1001))
        XCTAssertFalse(flow.explicitlyConfirm(digest: snapshot.confirmationDigest,
                                             trustedNowSeconds: 1040))
        XCTAssertTrue(flow.explicitlyConfirm(digest: snapshot.confirmationDigest,
                                            trustedNowSeconds: 1001))
        XCTAssertNotNil(flow.consumeConfirmed(trustedNowSeconds: 1002))
        XCTAssertNil(flow.consumeConfirmed(trustedNowSeconds: 1002))
    }
    func testReplacedReviewRequiresNewConfirmation() throws {
        let first = try make()
        let second = try make(payload: Data("different".utf8),
                              bindingPayload: Data("different".utf8))
        let flow = ReviewerConfirmationSession(presentation: first)
        XCTAssertTrue(flow.explicitlyConfirm(digest: first.confirmationDigest,
                                            trustedNowSeconds: 1001))
        flow.replace(with: second)
        XCTAssertFalse(flow.explicitlyConfirm(digest: first.confirmationDigest,
                                             trustedNowSeconds: 1001))
        XCTAssertNil(flow.consumeConfirmed(trustedNowSeconds: 1001))
        XCTAssertTrue(flow.explicitlyConfirm(digest: second.confirmationDigest,
                                            trustedNowSeconds: 1001))
    }
    func testDeniedRequestCannotBeConfirmed() throws {
        let snapshot = try make()
        let flow = ReviewerConfirmationSession(presentation: snapshot)
        flow.deny()
        XCTAssertFalse(flow.explicitlyConfirm(digest: snapshot.confirmationDigest,
                                             trustedNowSeconds: 1002))
        XCTAssertNil(flow.consumeConfirmed(trustedNowSeconds: 1002))
    }
    func testConfirmedButExpiredAtConsumptionIsDenied() throws {
        let snapshot = try make()
        let flow = ReviewerConfirmationSession(presentation: snapshot)
        XCTAssertTrue(flow.explicitlyConfirm(digest: snapshot.confirmationDigest,
                                            trustedNowSeconds: 1001))
        XCTAssertNil(flow.consumeConfirmed(trustedNowSeconds: 1040))
        XCTAssertEqual(flow.status, .consumed)
    }
}
#endif
