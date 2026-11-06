#if os(macOS)
import Foundation
import Security
import LocalAuthentication
import ShieldNativeContract

/// Reference API for a separately signed reviewer application, NOT a helper or agent.
/// The main XPC service still denies every approval and has no egress route.
/// Real enrollment requires a Developer Team-signed reviewer bundle and Secure Enclave.
public enum ReviewerKeyStoreError: Error {
    case untrustedReviewer
    case accessControlUnavailable
    case keyGenerationFailed(String)
    case publicKeyUnavailable
}

/// No software-private-key fallback, no embedded signing secret, no agent-facing API.
public struct ReviewerKeyStore {
    public let configuration: SignedPeerConfiguration
    public static let tagPrefix = "com.creativeipshield.review-signing.v1."

    public init(configuration: SignedPeerConfiguration) {
        self.configuration = configuration
    }

    public var applicationTag: Data {
        Data((Self.tagPrefix + configuration.reviewerBundleID).utf8)
    }

    /// Device-only key, unlocked session, explicit biometric/passcode presence on use.
    public func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let value = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &error
        ) else {
            _ = error?.takeRetainedValue()
            throw ReviewerKeyStoreError.accessControlUnavailable
        }
        return value
    }

    public func makeKeyGenerationAttributes(access: SecAccessControl) -> [String: Any] {
        [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessControl as String: access
            ]
        ]
    }

    /// Before even creating a key, verify this is the configured reviewer app.
    /// A bundle ID alone is not proof; OS signing must match the expected Team ID.
    public func isAuthorizedRunningReviewer() -> Bool {
        guard Bundle.main.bundleIdentifier == configuration.reviewerBundleID else { return false }
        var requirement: SecRequirement?
        let expression = configuration.requirement(for: .reviewer)
        guard SecRequirementCreateWithString(
            expression as CFString, SecCSFlags(rawValue: 0), &requirement
        ) == errSecSuccess, let requirement else { return false }
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, SecCSFlags(rawValue: 0), requirement) == errSecSuccess
    }

    /// Not called by CI. The Secure Enclave must create the non-exportable key.
    /// This does NOT issue an approval; UI, user verification and scoped signed
    /// authorization are separate future work.
    public func enroll() throws -> Data {
        guard isAuthorizedRunningReviewer() else {
            throw ReviewerKeyStoreError.untrustedReviewer
        }
        let access = try makeAccessControl()
        let attributes = makeKeyGenerationAttributes(access: access)
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "Secure Enclave unavailable"
            throw ReviewerKeyStoreError.keyGenerationFailed(reason)
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ReviewerKeyStoreError.publicKeyUnavailable
        }
        var exportError: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
            _ = exportError?.takeRetainedValue()
            throw ReviewerKeyStoreError.publicKeyUnavailable
        }
        return bytes
    }
}
#endif
