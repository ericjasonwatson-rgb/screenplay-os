import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Generation consent and activity")
struct GenerationConsentTests {
    let projectID = UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
    let jobID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
    let targetID = UUID(uuidString: "63000000-0000-0000-0000-000000000003")!
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let digest = String(repeating: "c", count: 64)

    func job(model: String = "fixture-v1") throws -> GenerationJobRecord {
        let request = GenerationRequestSnapshot(prompt: "Exact approved prompt", parameters: ["aspect_ratio": "16:9"])
        return .init(id: jobID, projectID: projectID, capability: .image, providerID: "mock", modelID: model,
                     target: .init(kind: .board, id: targetID, sourceRevision: digest), request: request,
                     requestSHA256: try request.sha256(), createdAt: instant, updatedAt: instant,
                     estimatedCost: .init(currency: "USD", amountMicros: 50_000))
    }

    @Test func consentRequiresTheCompleteCurrentPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try GenerationJobController(projectID: projectID, storageURL: root.appendingPathComponent("jobs.json"))
        try await controller.add(job())
        let draftPreview = try await controller.consentPreview(for: jobID)
        #expect(draftPreview.request.prompt == "Exact approved prompt")
        #expect(draftPreview.providerID == "mock")
        #expect(draftPreview.modelID == "fixture-v1")
        #expect(draftPreview.estimatedCost?.amountMicros == 50_000)
        try await controller.requestConsent(for: jobID, at: instant.addingTimeInterval(1))

        let changed = GenerationConsentPreview(job: try job(model: "different-model"))
        await #expect(throws: GenerationJobControllerError.consentPreviewChanged) {
            try await controller.grantConsent(for: jobID, matching: changed, at: instant.addingTimeInterval(2))
        }
        try await controller.grantConsent(for: jobID, matching: draftPreview, at: instant.addingTimeInterval(2))
    }

    @Test func activityContainsOnlySubmittedJobsAndNoTransportSecrets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try GenerationJobController(projectID: projectID, storageURL: root.appendingPathComponent("jobs.json"))
        try await controller.add(job())
        try await controller.requestConsent(for: jobID, at: instant.addingTimeInterval(1))
        let beforeSend = try await controller.consentPreview(for: jobID)
        try await controller.grantConsent(for: jobID, matching: beforeSend, at: instant.addingTimeInterval(2))
        #expect(try await controller.activityExport(generatedAt: instant).entries.isEmpty)

        try await controller.markSubmitted(jobID: jobID, at: instant.addingTimeInterval(3), providerTaskID: "private-task")
        let activity = try await controller.activityExport(generatedAt: instant.addingTimeInterval(4))
        #expect(activity.entries.map(\.id) == [jobID])
        let json = try #require(String(data: activity.jsonData(), encoding: .utf8))
        #expect(json.contains("Exact approved prompt"))
        #expect(!json.contains("private-task"))
        #expect(!json.localizedCaseInsensitiveContains("authorization"))
        #expect(!json.localizedCaseInsensitiveContains("api_key"))

        let destination = root.appendingPathComponent("Exports/ai-activity.json")
        try activity.write(to: destination)
        #expect(try Data(contentsOf: destination) == activity.jsonData())
    }

    @Test func costLedgerExportsSubmittedCostsWithoutInventingUnknownValues() async throws {
        var submitted = try job()
        submitted.status = .running
        submitted.consentedAt = instant
        submitted.submittedAt = instant.addingTimeInterval(2)
        submitted.updatedAt = instant.addingTimeInterval(2)
        let ledger = try GenerationCostLedger(ledger: .init(projectID: projectID, jobs: [submitted]))
        #expect(ledger.totals == ["USD": 50_000])
        let csv = String(decoding: ledger.csvData(), as: UTF8.self)
        #expect(csv.contains("mock,fixture-v1,image,board"))
        #expect(csv.contains("USD,50000,,"))

        let request = GenerationRequestSnapshot(prompt: "Unknown cost")
        var unknown = GenerationJobRecord(id: UUID(), projectID: projectID, capability: .text,
            providerID: "provider,quoted", modelID: "model", target: .init(kind: .scene, id: UUID(), sourceRevision: digest),
            request: request, requestSHA256: try request.sha256(), status: .running, createdAt: instant, updatedAt: instant,
            consentedAt: instant, submittedAt: instant)
        unknown.actualCost = nil
        let unknownCSV = String(decoding: try GenerationCostLedger(ledger: .init(projectID: projectID, jobs: [unknown])).csvData(), as: UTF8.self)
        #expect(unknownCSV.contains("\"provider,quoted\""))
        #expect(unknownCSV.hasSuffix(",,,,\n"))
    }
}
