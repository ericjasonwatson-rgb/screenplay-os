import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("AI connections and routing")
struct AIConnectionTests {
    let textID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    let mediaID = UUID(uuidString: "82000000-0000-0000-0000-000000000002")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func connection(id: UUID, service: String, capabilities: Set<AIConnectionCapability>,
                    models: [AIConnectionModel], status: AIConnectionStatus = .connected) -> AIConnection {
        .init(id: id, kind: .directProvider, serviceID: service, serviceName: service.capitalized,
              authMethod: .pastedKey, capabilities: capabilities, availableModels: models,
              status: status, createdAt: now, lastVerifiedAt: now,
              credentialReference: "keychain:\(id.uuidString)")
    }

    @Test func catalogRoundTripsWithoutCredentialsAndRejectsBadDefaults() throws {
        let text = connection(id: textID, service: "text", capabilities: [.text],
            models: [.init(id: "text-1", displayName: "Text 1", capabilities: [.text])])
        let catalog = try AIConnectionCatalog(connections: [text],
            defaults: .init(routes: [.text: .init(connectionID: textID, modelID: "text-1")]),
            monthlyBudgetMicros: 10_000_000, budgetCurrency: "USD").validated()
        let data = try JSONEncoder().encode(catalog)
        #expect(try JSONDecoder().decode(AIConnectionCatalog.self, from: data).validated() == catalog)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.localizedCaseInsensitiveContains("api_key"))
        #expect(!json.localizedCaseInsensitiveContains("authorization"))

        #expect(throws: AIConnectionValidationError.invalidDefault) {
            try AIConnectionCatalog(connections: [text], defaults: .init(routes: [
                .image: .init(connectionID: textID, modelID: "text-1")
            ])).validated()
        }
    }

    @Test func routerUsesCapabilityDefaultsAndExplainsMissingCoverage() throws {
        let text = connection(id: textID, service: "text", capabilities: [.text],
            models: [.init(id: "text-1", displayName: "Text 1", capabilities: [.text])])
        let media = connection(id: mediaID, service: "media", capabilities: [.image, .video], models: [
            .init(id: "image-1", displayName: "Image 1", capabilities: [.image]),
            .init(id: "video-1", displayName: "Video 1", capabilities: [.video])
        ])
        let catalog = AIConnectionCatalog(connections: [text, media], defaults: .init(routes: [
            .text: .init(connectionID: textID, modelID: "text-1"),
            .image: .init(connectionID: mediaID, modelID: "image-1")
        ]))
        #expect(try AIConnectionRouter().route(.init(capability: .image), catalog: catalog) ==
            .init(connectionID: mediaID, modelID: "image-1"))
        #expect(try AIConnectionRouter().route(.init(capability: .video, connectionID: mediaID), catalog: catalog) ==
            .init(connectionID: mediaID, modelID: "video-1"))
        #expect(throws: AIConnectionRoutingError.missingCapability(.voice)) {
            try AIConnectionRouter().route(.init(capability: .voice), catalog: catalog)
        }
    }

    @Test func organizationPolicyOverridesUserChoiceAndBlocksDisallowedService() throws {
        let text = connection(id: textID, service: "text", capabilities: [.text],
            models: [.init(id: "text-1", displayName: "Text 1", capabilities: [.text])])
        let media = connection(id: mediaID, service: "media", capabilities: [.text],
            models: [.init(id: "media-text", displayName: "Media Text", capabilities: [.text])])
        let catalog = AIConnectionCatalog(connections: [text, media])
        let policy = AIOrganizationPolicy(organizationName: "Studio", allowedServiceIDs: ["media"],
            allowedModelIDs: ["media": ["media-text"]],
            requiredRoutes: [.text: .init(connectionID: mediaID, modelID: "media-text")],
            credentialReference: "org-keychain:studio")
        #expect(try AIConnectionRouter().route(.init(capability: .text, connectionID: textID, modelID: "text-1"),
            catalog: catalog, organization: policy) == .init(connectionID: mediaID, modelID: "media-text"))

        let blocked = AIOrganizationPolicy(organizationName: "Studio", allowedServiceIDs: ["text"],
            requiredRoutes: [.text: .init(connectionID: mediaID, modelID: "media-text")],
            credentialReference: "org-keychain:studio")
        #expect(throws: AIConnectionRoutingError.organizationPolicyBlocked) {
            try AIConnectionRouter().route(.init(capability: .text), catalog: catalog, organization: blocked)
        }
        let invalid = AIOrganizationPolicy(organizationName: "", allowedServiceIDs: [], credentialReference: "")
        #expect(throws: AIConnectionValidationError.invalidConnection) { try invalid.validated() }
    }

    @Test func legacyMigrationReferencesExistingKeychainItemWithoutCopyingIt() {
        let record = LegacyDialogueConnectionMigration.record(id: textID, providerID: "openai",
            serviceName: "OpenAI", modelID: "chosen-model", hasCredential: true, migratedAt: now)
        #expect(record.status == .needsAttention)
        #expect(record.credentialReference == "legacy-dialogue:openai")
        #expect(record.availableModels.map(\.id) == ["chosen-model"])
    }
}
