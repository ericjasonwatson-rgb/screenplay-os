#if os(macOS)
import CryptoKit
import Foundation
import ShieldApprovalContract

public enum ReviewPreviewError: Error, Equatable {
    case contentMismatch
    case policyMismatch
    case cannotDisplayFullText
    case tooLargeToReview
}

/// A UI-only display of ALL bytes to be authorized, never a transport object.
/// Must come from the trusted gateway (not an AI agent's own description).
/// V1 permits textual content only and rejects binary/partial previews.
public struct ReviewPresentation {
    public static let maximumReviewBytes = 16_384
    public let binding: ApprovalRequestBinding
    public let completeContent: String
    public let effectivePolicy: String
    public let confirmationDigest: String

    public init(binding: ApprovalRequestBinding, contentBytes: Data,
                effectivePolicyBytes: Data) throws {
        guard contentBytes.count <= Self.maximumReviewBytes,
              effectivePolicyBytes.count <= Self.maximumReviewBytes else {
            throw ReviewPreviewError.tooLargeToReview
        }
        guard let content = String(data: contentBytes, encoding: .utf8),
              let policy = String(data: effectivePolicyBytes, encoding: .utf8),
              Self.readable(content), Self.readable(policy) else {
            throw ReviewPreviewError.cannotDisplayFullText
        }
        guard binding.payloadByteCount == Int64(contentBytes.count),
              Self.hash(contentBytes) == binding.contentSHA256 else {
            throw ReviewPreviewError.contentMismatch
        }
        guard Self.hash(effectivePolicyBytes) == binding.policySHA256 else {
            throw ReviewPreviewError.policyMismatch
        }
        self.binding = binding
        self.completeContent = content
        self.effectivePolicy = policy
        self.confirmationDigest = Self.hash(binding.canonicalBytes)
    }

    private static func readable(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { character in
            let scalar = character.value
            if scalar == 9 || scalar == 10 || scalar == 13 { return true }
            if scalar < 32 || (127...159).contains(scalar) { return false }
            // Hide direction overrides / isolate markers from approval UI.
            if (0x202A...0x202E).contains(scalar) ||
               (0x2066...0x2069).contains(scalar) { return false }
            return true
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// State checks only. Explicit confirmation is NOT authentication or approval.
/// Only a separately signed reviewer app may call a protected signer, and the
/// production gateway must independently reverify the signature and policy.
public final class ReviewerConfirmationSession {
    public enum Status: Equatable {
        case needsReview, confirmed, denied, consumed
    }
    public private(set) var status: Status = .needsReview
    /// Mutation epoch, so an async OS prompt cannot sign a replaced review.
    public private(set) var generation: UInt64 = 0
    private var presentation: ReviewPresentation

    public init(presentation: ReviewPresentation) {
        self.presentation = presentation
    }

    public func replace(with value: ReviewPresentation) {
        presentation = value
        generation &+= 1
        status = .needsReview
    }

    @discardableResult
    public func explicitlyConfirm(digest: String, trustedNowSeconds: Int64) -> Bool {
        guard status == .needsReview,
              presentation.binding.isWithinLifetime(at: trustedNowSeconds),
              digest == presentation.confirmationDigest else { return false }
        status = .confirmed
        generation &+= 1
        return true
    }

    public func deny() {
        status = .denied
        generation &+= 1
    }

    /// One-use UI handoff only; no cryptographic authorization is produced.
    public func consumeConfirmed(trustedNowSeconds: Int64) -> ApprovalRequestBinding? {
        guard status == .confirmed else { return nil }
        status = .consumed
        generation &+= 1
        return presentation.binding.isWithinLifetime(at: trustedNowSeconds) ?
            presentation.binding : nil
    }
}
#endif
