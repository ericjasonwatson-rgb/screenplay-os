#if os(macOS)
import CryptoKit
import Foundation
import ShieldApprovalContract

/// A detached signature, not an executable authorization or a signing key.
/// The peer may supply this object, but MUST NOT supply the trusted key registry.
public struct ReviewerApprovalSignature {
    public let reviewerKeyID: String
    public let signatureDER: Data

    public init(reviewerKeyID: String, signatureDER: Data) {
        self.reviewerKeyID = reviewerKeyID
        self.signatureDER = signatureDER
    }
}

public enum ApprovalVerificationError: Error, Equatable {
    case invalidTrustConfiguration
    case unknownReviewer
    case expiredOrNotYetValid
    case invalidSignature
    case previouslyConsumed
}

/// Shared, versioned message to be signed by a separately trusted reviewer.
/// Includes canonical content, policy, destination and expiry via the binding.
/// DO NOT sign JSON or caller-provided arbitrary bytes as an authorization.
public enum ReviewerApprovalMessage {
    public static func bytes(for expected: ApprovalRequestBinding) -> Data {
        var data = Data("CIPS-APPROVAL-GRANT-V1\n".utf8)
        data.append(expected.canonicalBytes)
        return data
    }
}

/// Validation-only in-memory one-use verifier. The native helper uses it only
/// for the isolated signed XPC sample, separate from ordinary approval calls.
/// A production service must use durable, crash-safe spent-ID storage.
public final class EphemeralApprovalVerifier {
    private let trustedKeys: [String: P256.Signing.PublicKey]
    private var consumed: Set<String> = []
    private let lock = NSLock()

    /// Key material MUST be loaded from independently trusted/managed
    /// configuration, never from an agent request or the approval itself.
    public init(trustedReviewerKeys: [String: Data]) throws {
        guard !trustedReviewerKeys.isEmpty else {
            throw ApprovalVerificationError.invalidTrustConfiguration
        }
        var parsed: [String: P256.Signing.PublicKey] = [:]
        for (keyID, rawKey) in trustedReviewerKeys {
            guard Self.validKeyID(keyID),
                  rawKey.count == 65, rawKey.first == 0x04,
                  let publicKey = try? P256.Signing.PublicKey(x963Representation: rawKey) else {
                throw ApprovalVerificationError.invalidTrustConfiguration
            }
            parsed[keyID] = publicKey
        }
        self.trustedKeys = parsed
    }

    /// Stateless cryptographic check for a later, separately durable claim.
    /// Never use this by itself to authorize dispatch; it has no replay storage.
    @discardableResult
    public func verifySignature(
        _ approval: ReviewerApprovalSignature,
        for expected: ApprovalRequestBinding,
        atTrustedTime nowSeconds: Int64
    ) -> Result<Void, ApprovalVerificationError> {
        guard expected.isWithinLifetime(at: nowSeconds) else {
            return .failure(.expiredOrNotYetValid)
        }
        guard let key = trustedKeys[approval.reviewerKeyID] else {
            return .failure(.unknownReviewer)
        }
        guard approval.signatureDER.count >= 8,
              approval.signatureDER.count <= 144,
              let signature = try? P256.Signing.ECDSASignature(
                  derRepresentation: approval.signatureDER
              ),
              key.isValidSignature(signature, for: ReviewerApprovalMessage.bytes(for: expected)) else {
            return .failure(.invalidSignature)
        }
        return .success(())
    }

    /// Reference-only in-memory one-use check. It is NOT durable on restart.
    @discardableResult
    public func verifyAndConsume(
        _ approval: ReviewerApprovalSignature,
        for expected: ApprovalRequestBinding,
        atTrustedTime nowSeconds: Int64
    ) -> Result<Void, ApprovalVerificationError> {
        switch verifySignature(approval, for: expected, atTrustedTime: nowSeconds) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        let unique = expected.projectID.uuidString + ":" + expected.requestID.uuidString
        lock.lock()
        defer { lock.unlock() }
        guard consumed.insert(unique).inserted else {
            return .failure(.previouslyConsumed)
        }
        return .success(())
    }

    private static func validKeyID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64,
              let first = value.utf8.first,
              (97...122).contains(first) || (48...57).contains(first) else { return false }
        return value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
#endif
