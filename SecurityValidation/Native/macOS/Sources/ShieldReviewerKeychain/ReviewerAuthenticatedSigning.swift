#if os(macOS)
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import ShieldApprovalVerification
import ShieldReviewerReview

/// A future separately signed reviewer app can use this explicit path.
/// Not linked into the helper or agent target. No egress or approval dispatch.
public enum ReviewerSigningError: Error {
    case reviewNotConfirmed
    case changedOrCanceledDuringAuthentication
    case authenticationUnavailable
    case authenticationDenied
    case protectedKeyUnavailable
    case keyNotSecureEnclaveBacked
    case unsupportedSigningAlgorithm
    case signatureFailed
    case publicKeyUnavailable
}

extension ReviewerKeyStore {
    /// Non-secret query builder, testable without creating a key or prompting.
    /// OS Keychain isolation and entitlement control still require real-device
    /// validation under a properly signed reviewer app.
    public func protectedSigningKeyQuery(using context: LAContext) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: applicationTag,
            kSecUseAuthenticationContext as String: context,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    /// Requires a matching signed reviewer app, exact UI-confirmed request,
    /// a fresh OS owner-authentication ceremony, and a pre-enrolled Secure
    /// Enclave private key. No software key fallback or automatic enrollment.
    ///
    /// Production must authenticate the *source* of the review request and
    /// independently verify/consume any signature at the trusted helper.
    @MainActor
    public func signExplicitReview(
        _ preview: ReviewPresentation,
        confirmation: ReviewerConfirmationSession
    ) async throws -> ReviewerApprovalSignature {
        // The first test on an unsigned/ad-hoc CI process must fail here,
        // BEFORE any key lookup or LocalAuthentication prompt.
        guard isAuthorizedRunningReviewer() else {
            throw ReviewerKeyStoreError.untrustedReviewer
        }
        let currentTime = Int64(Date().timeIntervalSince1970)
        guard let confirmed = confirmation.consumeConfirmed(
            trustedNowSeconds: currentTime
        ), confirmed.canonicalBytes == preview.binding.canonicalBytes else {
            throw ReviewerSigningError.reviewNotConfirmed
        }
        let confirmedGeneration = confirmation.generation
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { context.invalidate() }

        var availableError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &availableError
        ) else {
            throw ReviewerSigningError.authenticationUnavailable
        }
        let granted: Bool
        do {
            granted = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Approve the exact reviewed AI transfer"
            )
        } catch {
            throw ReviewerSigningError.authenticationDenied
        }
        guard granted else { throw ReviewerSigningError.authenticationDenied }

        // A review replacement, denial or another consumption while the
        // system dialog is open must invalidate this signing attempt.
        guard confirmation.generation == confirmedGeneration,
              confirmation.status == .consumed,
              preview.binding.isWithinLifetime(
                at: Int64(Date().timeIntervalSince1970)
              ),
              isAuthorizedRunningReviewer() else {
            throw ReviewerSigningError.changedOrCanceledDuringAuthentication
        }

        // Require a Secure Enclave token at lookup, AND verify the returned
        // SecKey attributes. Failure never falls back to a software key.
        let query = protectedSigningKeyQuery(using: context)
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let found else {
            throw ReviewerSigningError.protectedKeyUnavailable
        }
        let privateKey = found as! SecKey
        // Do not accept a software-generated or imported P-256 private key
        // with the same application tag as a fallback.
        guard let attrs = SecKeyCopyAttributes(privateKey) as? [String: Any],
              let tokenID = attrs[kSecAttrTokenID as String] as? String,
              tokenID == (kSecAttrTokenIDSecureEnclave as String) else {
            throw ReviewerSigningError.keyNotSecureEnclaveBacked
        }
        guard SecKeyIsAlgorithmSupported(
            privateKey, .sign, .ecdsaSignatureMessageX962SHA256
        ) else {
            throw ReviewerSigningError.unsupportedSigningAlgorithm
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ReviewerSigningError.publicKeyUnavailable
        }
        var publicError: Unmanaged<CFError>?
        guard let publicBytes = SecKeyCopyExternalRepresentation(
            publicKey, &publicError
        ) as Data? else {
            _ = publicError?.takeRetainedValue()
            throw ReviewerSigningError.publicKeyUnavailable
        }
        guard publicBytes.count == 65, publicBytes.first == 0x04 else {
            throw ReviewerSigningError.publicKeyUnavailable
        }

        let message = ReviewerApprovalMessage.bytes(for: confirmed)
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256,
            message as CFData, &signingError
        ) as Data? else {
            _ = signingError?.takeRetainedValue()
            throw ReviewerSigningError.signatureFailed
        }
        guard confirmation.generation == confirmedGeneration,
              isAuthorizedRunningReviewer() else {
            throw ReviewerSigningError.changedOrCanceledDuringAuthentication
        }

        let keyID = SHA256.hash(data: publicBytes).map {
            String(format: "%02x", $0)
        }.joined()
        return ReviewerApprovalSignature(
            reviewerKeyID: keyID, signatureDER: signature
        )
    }
}
#endif
