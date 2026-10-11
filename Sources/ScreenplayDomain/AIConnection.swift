import Foundation

public enum AIConnectionKind: String, Codable, CaseIterable, Sendable {
    case aggregator
    case directProvider = "direct_provider"
    case organization
    case managed
}

public enum AIConnectionAuthMethod: String, Codable, CaseIterable, Sendable {
    case oauth
    case pastedKey = "pasted_key"
    case organizationIssued = "organization_issued"
}

public enum AIConnectionCapability: String, Codable, CaseIterable, Sendable {
    case text, image, video, voice, music
}

public enum AIConnectionStatus: String, Codable, CaseIterable, Sendable {
    case connected
    case needsAttention = "needs_attention"
    case revoked
}

public struct AIConnectionModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<AIConnectionCapability>

    public init(id: String, displayName: String, capabilities: Set<AIConnectionCapability>) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

/// Local service metadata only. credentialReference identifies a Keychain item;
/// it is never the credential itself.
public struct AIConnection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AIConnectionKind
    public let serviceID: String
    public let serviceName: String
    public let authMethod: AIConnectionAuthMethod
    public let capabilities: Set<AIConnectionCapability>
    public var availableModels: [AIConnectionModel]
    public var status: AIConnectionStatus
    public let createdAt: Date
    public var lastVerifiedAt: Date?
    public var spendingNotes: String?
    public let credentialReference: String?

    public init(id: UUID, kind: AIConnectionKind, serviceID: String, serviceName: String,
                authMethod: AIConnectionAuthMethod, capabilities: Set<AIConnectionCapability>,
                availableModels: [AIConnectionModel] = [], status: AIConnectionStatus,
                createdAt: Date, lastVerifiedAt: Date? = nil, spendingNotes: String? = nil,
                credentialReference: String? = nil) {
        self.id = id
        self.kind = kind
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.authMethod = authMethod
        self.capabilities = capabilities
        self.availableModels = availableModels
        self.status = status
        self.createdAt = createdAt
        self.lastVerifiedAt = lastVerifiedAt
        self.spendingNotes = spendingNotes
        self.credentialReference = credentialReference
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, capabilities, status
        case serviceID = "service_id"
        case serviceName = "service_name"
        case authMethod = "auth_method"
        case availableModels = "available_models"
        case createdAt = "created_at"
        case lastVerifiedAt = "last_verified_at"
        case spendingNotes = "spending_notes"
        case credentialReference = "credential_reference"
    }
}

public struct AIConnectionRoute: Codable, Equatable, Sendable {
    public let connectionID: UUID
    public let modelID: String

    public init(connectionID: UUID, modelID: String) {
        self.connectionID = connectionID
        self.modelID = modelID
    }
}

public struct AIConnectionDefaults: Codable, Equatable, Sendable {
    public var routes: [AIConnectionCapability: AIConnectionRoute]
    public init(routes: [AIConnectionCapability: AIConnectionRoute] = [:]) { self.routes = routes }
}

public struct AIConnectionCatalog: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public var connections: [AIConnection]
    public var defaults: AIConnectionDefaults
    public var monthlyBudgetMicros: Int64?
    public var budgetCurrency: String?

    public init(version: Int = AIConnectionCatalog.currentVersion, connections: [AIConnection] = [],
                defaults: AIConnectionDefaults = .init(), monthlyBudgetMicros: Int64? = nil,
                budgetCurrency: String? = nil) {
        self.version = version
        self.connections = connections
        self.defaults = defaults
        self.monthlyBudgetMicros = monthlyBudgetMicros
        self.budgetCurrency = budgetCurrency
    }

    enum CodingKeys: String, CodingKey {
        case version, connections, defaults
        case monthlyBudgetMicros = "monthly_budget_micros"
        case budgetCurrency = "budget_currency"
    }

    public func validated() throws -> AIConnectionCatalog {
        guard version == Self.currentVersion else { throw AIConnectionValidationError.unsupportedVersion }
        guard Set(connections.map(\.id)).count == connections.count else { throw AIConnectionValidationError.duplicateConnection }
        for connection in connections {
            guard Self.nonempty(connection.serviceID, maximum: 200),
                  Self.nonempty(connection.serviceName, maximum: 200),
                  !connection.capabilities.isEmpty,
                  connection.lastVerifiedAt.map({ $0 >= connection.createdAt }) ?? true,
                  connection.spendingNotes.map({ $0.utf8.count <= 2_000 }) ?? true,
                  connection.credentialReference.map({ Self.nonempty($0, maximum: 500) }) ?? true,
                  Set(connection.availableModels.map(\.id)).count == connection.availableModels.count else {
                throw AIConnectionValidationError.invalidConnection
            }
            for model in connection.availableModels {
                guard Self.nonempty(model.id, maximum: 300), Self.nonempty(model.displayName, maximum: 300),
                      !model.capabilities.isEmpty, model.capabilities.isSubset(of: connection.capabilities) else {
                    throw AIConnectionValidationError.invalidModel
                }
            }
        }
        if let budget = monthlyBudgetMicros {
            guard budget >= 0, let currency = budgetCurrency,
                  currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
                throw AIConnectionValidationError.invalidBudget
            }
        } else if budgetCurrency != nil { throw AIConnectionValidationError.invalidBudget }
        for (capability, route) in defaults.routes {
            guard let connection = connections.first(where: { $0.id == route.connectionID }),
                  connection.capabilities.contains(capability),
                  connection.availableModels.contains(where: { $0.id == route.modelID && $0.capabilities.contains(capability) }) else {
                throw AIConnectionValidationError.invalidDefault
            }
        }
        return self
    }

    private static func nonempty(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
    }
}

public enum AIConnectionValidationError: Error, Equatable {
    case unsupportedVersion, duplicateConnection, invalidConnection, invalidModel, invalidDefault, invalidBudget
}

public struct AIOrganizationPolicy: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let organizationName: String
    public let allowedServiceIDs: Set<String>
    public let allowedModelIDs: [String: Set<String>]
    public let perSeatMonthlyBudgetMicros: Int64?
    public let budgetCurrency: String?
    public let requiredRoutes: [AIConnectionCapability: AIConnectionRoute]
    public let credentialReference: String

    public init(version: Int = AIOrganizationPolicy.currentVersion, organizationName: String,
                allowedServiceIDs: Set<String>, allowedModelIDs: [String: Set<String>] = [:],
                perSeatMonthlyBudgetMicros: Int64? = nil, budgetCurrency: String? = nil,
                requiredRoutes: [AIConnectionCapability: AIConnectionRoute] = [:], credentialReference: String) {
        self.version = version
        self.organizationName = organizationName
        self.allowedServiceIDs = allowedServiceIDs
        self.allowedModelIDs = allowedModelIDs
        self.perSeatMonthlyBudgetMicros = perSeatMonthlyBudgetMicros
        self.budgetCurrency = budgetCurrency
        self.requiredRoutes = requiredRoutes
        self.credentialReference = credentialReference
    }

    public func validated() throws -> AIOrganizationPolicy {
        guard version == Self.currentVersion else { throw AIConnectionValidationError.unsupportedVersion }
        guard !organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              organizationName.utf8.count <= 300, !allowedServiceIDs.isEmpty,
              allowedServiceIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 200 }),
              !credentialReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              credentialReference.utf8.count <= 500,
              requiredRoutes.values.allSatisfy({ !$0.modelID.isEmpty && $0.modelID.utf8.count <= 300 }) else {
            throw AIConnectionValidationError.invalidConnection
        }
        if let budget = perSeatMonthlyBudgetMicros {
            guard budget >= 0, let currency = budgetCurrency,
                  currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
                throw AIConnectionValidationError.invalidBudget
            }
        } else if budgetCurrency != nil { throw AIConnectionValidationError.invalidBudget }
        for (service, models) in allowedModelIDs {
            guard allowedServiceIDs.contains(service), !models.isEmpty,
                  models.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 300 }) else {
                throw AIConnectionValidationError.invalidModel
            }
        }
        return self
    }
}

public struct AIConnectionRoutingRequest: Equatable, Sendable {
    public let capability: AIConnectionCapability
    public let connectionID: UUID?
    public let modelID: String?
    public init(capability: AIConnectionCapability, connectionID: UUID? = nil, modelID: String? = nil) {
        self.capability = capability
        self.connectionID = connectionID
        self.modelID = modelID
    }
}

public struct AIConnectionRouter {
    public init() {}

    public func route(_ request: AIConnectionRoutingRequest, catalog: AIConnectionCatalog,
                      organization: AIOrganizationPolicy? = nil) throws -> AIConnectionRoute {
        let catalog = try catalog.validated()
        let organization = try organization?.validated()
        let forced = organization?.requiredRoutes[request.capability]
        let eligible = catalog.connections.filter { connection in
            connection.status == .connected && connection.capabilities.contains(request.capability) &&
            (organization?.allowedServiceIDs.contains(connection.serviceID) ?? true)
        }
        guard !eligible.isEmpty else { throw AIConnectionRoutingError.missingCapability(request.capability) }

        if let preferred = forced {
            guard let connection = eligible.first(where: { $0.id == preferred.connectionID }) else {
                throw AIConnectionRoutingError.organizationPolicyBlocked
            }
            guard allowed(modelID: preferred.modelID, for: connection, capability: request.capability,
                          organization: organization) else { throw AIConnectionRoutingError.organizationPolicyBlocked }
            return preferred
        }
        if let requestedID = request.connectionID {
            guard let connection = eligible.first(where: { $0.id == requestedID }) else {
                throw AIConnectionRoutingError.connectionUnavailable
            }
            if let requestedModel = request.modelID {
                guard allowed(modelID: requestedModel, for: connection, capability: request.capability,
                              organization: organization) else { throw AIConnectionRoutingError.modelUnavailable }
                return .init(connectionID: requestedID, modelID: requestedModel)
            }
            guard let model = firstAllowedModel(in: connection, capability: request.capability, organization: organization) else {
                throw AIConnectionRoutingError.modelUnavailable
            }
            return .init(connectionID: requestedID, modelID: model.id)
        }
        if request.modelID == nil, let preferred = catalog.defaults.routes[request.capability] {
            guard let connection = eligible.first(where: { $0.id == preferred.connectionID }) else {
                throw AIConnectionRoutingError.connectionUnavailable
            }
            guard allowed(modelID: preferred.modelID, for: connection, capability: request.capability,
                          organization: organization) else { throw AIConnectionRoutingError.modelUnavailable }
            return preferred
        }
        for connection in eligible {
            if let model = firstAllowedModel(in: connection, capability: request.capability,
                                             requestedModelID: request.modelID, organization: organization) {
                return .init(connectionID: connection.id, modelID: model.id)
            }
        }
        throw AIConnectionRoutingError.modelUnavailable
    }

    private func firstAllowedModel(in connection: AIConnection, capability: AIConnectionCapability,
                                   requestedModelID: String? = nil,
                                   organization: AIOrganizationPolicy?) -> AIConnectionModel? {
        connection.availableModels.first {
            $0.capabilities.contains(capability) && (requestedModelID == nil || $0.id == requestedModelID) &&
            (organization?.allowedModelIDs[connection.serviceID]?.contains($0.id) ?? true)
        }
    }

    private func allowed(modelID: String, for connection: AIConnection, capability: AIConnectionCapability,
                         organization: AIOrganizationPolicy?) -> Bool {
        connection.availableModels.contains { model in
            model.id == modelID && model.capabilities.contains(capability) &&
            (organization?.allowedModelIDs[connection.serviceID]?.contains(modelID) ?? true)
        }
    }
}

public enum AIConnectionRoutingError: Error, Equatable {
    case missingCapability(AIConnectionCapability)
    case connectionUnavailable, modelUnavailable, organizationPolicyBlocked
}

public enum LegacyDialogueConnectionMigration {
    public static func record(id: UUID, providerID: String, serviceName: String, modelID: String?,
                              hasCredential: Bool, migratedAt: Date) -> AIConnection {
        let models = modelID.flatMap { $0.isEmpty ? nil : $0 }.map {
            [AIConnectionModel(id: $0, displayName: $0, capabilities: [.text])]
        } ?? []
        return AIConnection(id: id, kind: .directProvider, serviceID: providerID, serviceName: serviceName,
            authMethod: .pastedKey, capabilities: [.text], availableModels: models, status: .needsAttention,
            createdAt: migratedAt, credentialReference: hasCredential ? "legacy-dialogue:\(providerID)" : nil)
    }
}
