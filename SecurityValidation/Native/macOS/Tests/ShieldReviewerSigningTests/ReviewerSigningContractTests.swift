#if os(macOS)
import CryptoKit
import Foundation
import Security
import LocalAuthentication
import XCTest
import ShieldApprovalContract
import ShieldNativeContract
import ShieldReviewerReview
import ShieldApprovalVerification
@testable import ShieldReviewerKeychain

final class ReviewerSigningContractTests: XCTestCase {
    private func preview() throws -> ReviewPresentation {
        let payload = Data("synthetic-only-content".utf8)
        let policy = Data("synthetic-only-policy".utf8)
        func hex(_ data: Data) -> String {
            SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
        }
        let now = Int64(Date().timeIntervalSince1970)
        let binding = try ApprovalRequestBinding(
            projectID: UUID(), requestID: UUID(),
            agentIdentity: "com.example.agent",
            destinationID: "test.provider", purpose: .analyze,
            contentSHA256: hex(payload), policySHA256: hex(policy),
            payloadByteCount: Int64(payload.count),
            issuedAtSeconds: now - 1, expiresAtSeconds: now + 60
        )
        return try ReviewPresentation(
            binding: binding, contentBytes: payload,
            effectivePolicyBytes: policy
        )
    }

    private func keyStore() throws -> ReviewerKeyStore {
        let config = try SignedPeerConfiguration(
            teamID: "AB12345678",
            agentBundleID: "com.example.shield.agent",
            reviewerBundleID: "com.example.shield.reviewer",
            helperBundleID: "com.example.shield.helper",
            agentMachService: "com.example.shield.agentservice",
            reviewerMachService: "com.example.shield.reviewservice"
        )
        return ReviewerKeyStore(configuration: config)
    }

    @MainActor
    func testAdHocTestRunnerCannotSignEvenAfterExplicitReview() async throws {
        let presentation = try preview()
        let session = ReviewerConfirmationSession(presentation: presentation)
        XCTAssertTrue(session.explicitlyConfirm(
            digest: presentation.confirmationDigest,
            trustedNowSeconds: presentation.binding.issuedAtSeconds + 1
        ))
        let store = try keyStore()
        XCTAssertFalse(store.isAuthorizedRunningReviewer())
        do {
            _ = try await store.signExplicitReview(
                presentation, confirmation: session
            )
            XCTFail("Unsigned or ad-hoc test runner must never sign")
        } catch ReviewerKeyStoreError.untrustedReviewer {
            XCTAssertEqual(session.status, .confirmed,
                           "Refused before consuming review or accessing Keychain")
        }
    }

    @MainActor
    func testMissingExplicitConfirmationDoesNotBecomeAuthorization() async throws {
        let presentation = try preview()
        let session = ReviewerConfirmationSession(presentation: presentation)
        let store = try keyStore()
        do {
            _ = try await store.signExplicitReview(
                presentation, confirmation: session
            )
            XCTFail("Signing should not run")
        } catch ReviewerKeyStoreError.untrustedReviewer {
            XCTAssertEqual(session.status, .needsReview)
        }
    }

    func testReviewMutationGenerationTracksReplacementAndDenial() throws {
        let original = try preview()
        let session = ReviewerConfirmationSession(presentation: original)
        let start = session.generation
        XCTAssertTrue(session.explicitlyConfirm(
            digest: original.confirmationDigest,
            trustedNowSeconds: original.binding.issuedAtSeconds + 1
        ))
        XCTAssertTrue(session.generation > start)
        let confirmed = session.generation
        session.replace(with: original)
        XCTAssertTrue(session.generation > confirmed)
        XCTAssertEqual(session.status, .needsReview)
        session.deny()
        XCTAssertEqual(session.status, .denied)
        XCTAssertNil(session.consumeConfirmed(
            trustedNowSeconds: original.binding.issuedAtSeconds + 1
        ))
    }
    /// This test-only key is explicitly SOFTWARE-HELD and nonpermanent.
    /// Its only purpose is interoperability: Security.framework's DER ECDSA
    /// signature must be understood by the independent CryptoKit verifier.
    /// Production ReviewerKeyStore rejects non-Secure Enclave private keys.
    func testSecurityFrameworkP256DERSignatureMatchesIndependentVerifier() throws {
        let request = try preview().binding
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]
        var keyError: Unmanaged<CFError>?
        let signingKey = try XCTUnwrap(
            SecKeyCreateRandomKey(attributes as CFDictionary, &keyError)
        )
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(signingKey))
        var publicError: Unmanaged<CFError>?
        let publicBytes = try XCTUnwrap(
            SecKeyCopyExternalRepresentation(publicKey, &publicError) as Data?
        )
        XCTAssertEqual(publicBytes.count, 65)
        XCTAssertEqual(publicBytes.first, 0x04)
        let id = SHA256.hash(data: publicBytes).map {
            String(format: "%02x", $0)
        }.joined()
        let message = ReviewerApprovalMessage.bytes(for: request)
        var signatureError: Unmanaged<CFError>?
        let der = try XCTUnwrap(
            SecKeyCreateSignature(
                signingKey,
                .ecdsaSignatureMessageX962SHA256,
                message as CFData,
                &signatureError
            ) as Data?
        )
        let verifier = try EphemeralApprovalVerifier(
            trustedReviewerKeys: [id: publicBytes]
        )
        let approval = ReviewerApprovalSignature(
            reviewerKeyID: id, signatureDER: der
        )
        switch verifier.verifySignature(
            approval, for: request,
            atTrustedTime: request.issuedAtSeconds + 1
        ) {
        case .success: break
        case .failure(let error):
            XCTFail("Security.framework DER signature rejected: \(error)")
        }
    }


    func testReviewerKeyLookupRequiresSecureEnclaveAndAuthenticationContext() throws {
        let store = try keyStore()
        let context = LAContext()
        defer { context.invalidate() }
        let query = store.protectedSigningKeyQuery(using: context)
        XCTAssertEqual(query[kSecAttrTokenID as String] as? String,
                       kSecAttrTokenIDSecureEnclave as String)
        XCTAssertEqual(query[kSecAttrApplicationTag as String] as? Data,
                       store.applicationTag)
        XCTAssertEqual(query[kSecAttrKeyClass as String] as? String,
                       kSecAttrKeyClassPrivate as String)
        XCTAssertNotNil(query[kSecUseAuthenticationContext as String] as? LAContext)
        XCTAssertEqual(query[kSecReturnRef as String] as? Bool, true)
        XCTAssertNil(query[kSecValueData as String])
    }


}
#endif
