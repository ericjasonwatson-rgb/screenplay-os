import Foundation

/// Platform-neutral fail-closed contract. No network or media access.
public enum ShieldRole: String, Codable, Equatable { case agent, reviewer }

public enum ConfigurationError: Error, Equatable {
    case invalidTeamIdentifier
    case invalidBundleIdentifier
    case reusedBundleIdentifier
    case invalidServiceIdentifier
    case reusedServiceIdentifier
}

/// Values must be embedded in a signed deployment bundle, never agent-supplied.
public struct SignedPeerConfiguration: Equatable {
    public let teamID: String
    public let agentBundleID: String
    public let reviewerBundleID: String
    public let helperBundleID: String
    public let agentMachService: String
    public let reviewerMachService: String

    public init(teamID: String, agentBundleID: String, reviewerBundleID: String,
                helperBundleID: String, agentMachService: String, reviewerMachService: String) throws {
        guard teamID.count == 10 && teamID.utf8.allSatisfy({
            (65...90).contains($0) || (48...57).contains($0)
        }) else { throw ConfigurationError.invalidTeamIdentifier }
        let bundles = [agentBundleID, reviewerBundleID, helperBundleID]
        guard bundles.allSatisfy(Self.validBundleID) else { throw ConfigurationError.invalidBundleIdentifier }
        guard Set(bundles).count == bundles.count else { throw ConfigurationError.reusedBundleIdentifier }
        let services = [agentMachService, reviewerMachService]
        guard services.allSatisfy(Self.validBundleID) else { throw ConfigurationError.invalidServiceIdentifier }
        guard agentMachService != reviewerMachService else { throw ConfigurationError.reusedServiceIdentifier }
        self.teamID = teamID
        self.agentBundleID = agentBundleID
        self.reviewerBundleID = reviewerBundleID
        self.helperBundleID = helperBundleID
        self.agentMachService = agentMachService
        self.reviewerMachService = reviewerMachService
    }

    private static func validBundleID(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard value.utf8.count <= 200, labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  let first = label.utf8.first, let last = label.utf8.last,
                  Self.isASCIIAlphaNumeric(first) && Self.isASCIIAlphaNumeric(last),
                  label.utf8.allSatisfy({ Self.isASCIIAlphaNumeric($0) || $0 == 45 }) else { return false }
        }
        return true
    }

    private static func isASCIIAlphaNumeric(_ value: UInt8) -> Bool {
        (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value)
    }

    public func requirement(for role: ShieldRole) -> String {
        Self.requirement(bundleID: role == .agent ? agentBundleID : reviewerBundleID, teamID: teamID)
    }

    public func helperRequirement() -> String {
        Self.requirement(bundleID: helperBundleID, teamID: teamID)
    }

    private static func requirement(bundleID: String, teamID: String) -> String {
        "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

public enum ShieldDenied: String, Codable {
    case nativeIntegrationPending = "native_integration_pending"
    case invalidMessage = "invalid_message"
    case wrongRole = "wrong_role"
    case unsupportedOperation = "unsupported_operation"
}

public struct DenialResponse: Codable, Equatable {
    public let status: String
    public let error: ShieldDenied
    public init(_ error: ShieldDenied) {
        status = "denied"
        self.error = error
    }
}

/// Always denies, even for valid signed identities. This code has no egress path.
public enum FailClosedCommandHandler {
    public static let maxBytes = 16_384
    private static let agentOperations: Set<String> = ["prepare", "submit"]
    private static let reviewerOperations: Set<String> = ["pending", "approve", "reject"]

    public static func response(to payload: Data, role: ShieldRole, requestedOperation: String) -> Data {
        guard payload.count <= maxBytes, !payload.isEmpty else { return encoded(.invalidMessage) }
        guard let json = try? JSONSerialization.jsonObject(with: payload),
              let dict = json as? [String: Any],
              dict.count == 1, dict["op"] as? String == requestedOperation else {
            return encoded(.invalidMessage)
        }
        let valid = role == .agent ? agentOperations : reviewerOperations
        guard valid.contains(requestedOperation) else { return encoded(.wrongRole) }
        return encoded(.nativeIntegrationPending)
    }

    private static func encoded(_ error: ShieldDenied) -> Data {
        (try? JSONEncoder().encode(DenialResponse(error))) ??
        Data("{\"status\":\"denied\",\"error\":\"invalid_message\"}".utf8)
    }
}
