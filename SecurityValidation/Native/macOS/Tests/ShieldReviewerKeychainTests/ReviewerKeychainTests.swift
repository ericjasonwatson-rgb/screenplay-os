#if os(macOS)
import Foundation
import Security
import XCTest
import ShieldNativeContract
@testable import ShieldReviewerKeychain

final class ReviewerKeychainTests: XCTestCase {
    func config() throws -> SignedPeerConfiguration {
        try SignedPeerConfiguration(
            teamID: "AB12345678",
            agentBundleID: "com.example.shield.agent",
            reviewerBundleID: "com.example.shield.reviewer",
            helperBundleID: "com.example.shield.helper",
            agentMachService: "com.example.shield.agentService",
            reviewerMachService: "com.example.shield.reviewerService"
        )
    }

    func testDistinctReviewerTagContainsNoSecret() throws {
        let store = ReviewerKeyStore(configuration: try config())
        XCTAssertEqual(
            String(data: store.applicationTag, encoding: .utf8),
            "com.creativeipshield.review-signing.v1.com.example.shield.reviewer"
        )
        XCTAssertFalse(store.applicationTag.isEmpty)
    }

    func testSecureEnclaveOnlyDeviceBoundAttributes() throws {
        let store = ReviewerKeyStore(configuration: try config())
        let attrs = try store.makeKeyGenerationAttributes(access: store.makeAccessControl())
        XCTAssertEqual(attrs[kSecAttrTokenID as String] as? String, kSecAttrTokenIDSecureEnclave as String)
        XCTAssertEqual(attrs[kSecAttrKeySizeInBits as String] as? Int, 256)
        let keys = try XCTUnwrap(attrs[kSecPrivateKeyAttrs as String] as? [String: Any])
        XCTAssertEqual(keys[kSecAttrApplicationTag as String] as? Data, store.applicationTag)
        XCTAssertEqual(keys[kSecAttrIsPermanent as String] as? Bool, true)
        XCTAssertNotNil(keys[kSecAttrAccessControl as String] as? SecAccessControl)
        XCTAssertNil(keys[kSecValueData as String])
        XCTAssertNil(attrs[kSecValueData as String])
    }

    func testUntrustedTestRunnerCannotEnrollOrCreateKey() throws {
        let store = ReviewerKeyStore(configuration: try config())
        XCTAssertFalse(store.isAuthorizedRunningReviewer())
        XCTAssertThrowsError(try store.enroll()) { error in
            guard case ReviewerKeyStoreError.untrustedReviewer = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAgentBundleCannotReuseReviewerIdentity() throws {
        let config = try config()
        XCTAssertNotEqual(config.requirement(for: .agent), config.requirement(for: .reviewer))
        XCTAssertFalse(ReviewerKeyStore(configuration: config).isAuthorizedRunningReviewer())
    }
}
#endif
