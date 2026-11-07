import Foundation

/// Canonical proposed-transfer context for future reviewer approval. This is NOT
/// an authorization token, signature, credential or live dispatch API.
public struct ApprovalRequestBinding: Equatable, Sendable {
    public enum Purpose: String, CaseIterable, Sendable {
        case analyze, summarize, transform, generate, export, publish, train
    }
    public enum ValidationError: Error, Equatable {
        case invalidIdentifier, invalidDigest, invalidLifetime, invalidPayloadSize
    }

    public static let maximumLifetimeSeconds: Int64 = 300
    public static let maximumPayloadBytes: Int64 = 1_073_741_824
    public let projectID: UUID
    public let requestID: UUID
    public let agentIdentity: String
    /// Trusted-gateway registered provider identifier, NOT an agent-supplied URL.
    public let destinationID: String
    public let purpose: Purpose
    public let contentSHA256: String
    public let policySHA256: String
    public let payloadByteCount: Int64
    public let issuedAtSeconds: Int64
    public let expiresAtSeconds: Int64

    public init(projectID: UUID, requestID: UUID, agentIdentity: String,
                destinationID: String, purpose: Purpose, contentSHA256: String,
                policySHA256: String, payloadByteCount: Int64,
                issuedAtSeconds: Int64, expiresAtSeconds: Int64) throws {
        guard Self.validIdentity(agentIdentity), Self.validIdentity(destinationID) else {
            throw ValidationError.invalidIdentifier
        }
        guard Self.validDigest(contentSHA256), Self.validDigest(policySHA256) else {
            throw ValidationError.invalidDigest
        }
        guard payloadByteCount >= 0, payloadByteCount <= Self.maximumPayloadBytes else {
            throw ValidationError.invalidPayloadSize
        }
        guard issuedAtSeconds >= 0, expiresAtSeconds > issuedAtSeconds,
              expiresAtSeconds - issuedAtSeconds <= Self.maximumLifetimeSeconds else {
            throw ValidationError.invalidLifetime
        }
        self.projectID = projectID
        self.requestID = requestID
        self.agentIdentity = agentIdentity
        self.destinationID = destinationID
        self.purpose = purpose
        self.contentSHA256 = contentSHA256
        self.policySHA256 = policySHA256
        self.payloadByteCount = payloadByteCount
        self.issuedAtSeconds = issuedAtSeconds
        self.expiresAtSeconds = expiresAtSeconds
    }

    /// Length-prefixed, deterministic UTF-8 encoding for a future signing layer.
    /// Domain separation prevents accidental reuse as another message type.
    public var canonicalBytes: Data {
        let fields = [
            "CIPS-REVIEW-REQUEST-V1",
            projectID.uuidString.lowercased(), requestID.uuidString.lowercased(),
            agentIdentity, destinationID, purpose.rawValue,
            contentSHA256, policySHA256,
            String(payloadByteCount), String(issuedAtSeconds), String(expiresAtSeconds)
        ]
        var result = Data()
        for field in fields {
            let bytes = Array(field.utf8)
            result.append(contentsOf: "\(bytes.count):".utf8)
            result.append(contentsOf: bytes)
        }
        return result
    }

    /// Structural validation is not an authorization decision. A trusted gateway
    /// must issue request IDs, authenticate identities and enforce one-time use.
    public func isWithinLifetime(at nowSeconds: Int64) -> Bool {
        nowSeconds >= issuedAtSeconds && nowSeconds < expiresAtSeconds
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func validIdentity(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128,
              value.utf8.first != 45, value.utf8.last != 45 else { return false }
        return value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95
        }
    }
}
