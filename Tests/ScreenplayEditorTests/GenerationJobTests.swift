import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Generation job records")
struct GenerationJobTests {
    let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let targetID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let jobID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let referenceID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let digest = String(repeating: "a", count: 64)

    func request() -> GenerationRequestSnapshot {
        .init(prompt: "Locked wide shot. Preserve the approved staging.", references: [
            .init(id: referenceID, kind: "approved_board", relativePath: "Media/Boards/board.png",
                  sha256: String(repeating: "b", count: 64), mediaType: "image/png")
        ], parameters: ["aspect_ratio": "16:9", "duration_seconds": "5"])
    }

    func job(status: GenerationJobStatus = .draft) throws -> GenerationJobRecord {
        let snapshot = request()
        let submitted = [.running, .succeeded, .failed].contains(status) ? instant : nil
        let completed = [.succeeded, .failed].contains(status) ? instant : nil
        return .init(id: jobID, projectID: projectID, capability: .video, providerID: "mock", modelID: "fixture-v1",
                     target: .init(kind: .shot, id: targetID, sourceRevision: digest), request: snapshot,
                     requestSHA256: try snapshot.sha256(), status: status, createdAt: instant, updatedAt: instant,
                     consentedAt: [.queued, .running, .succeeded, .failed].contains(status) ? instant : nil,
                     submittedAt: submitted, completedAt: completed,
                     estimatedCost: .init(currency: "USD", amountMicros: 280_000),
                     actualCost: status == .succeeded ? .init(currency: "USD", amountMicros: 275_000) : nil,
                     sanitizedError: status == .failed ? "Provider rejected the request." : nil,
                     providerTaskID: submitted == nil ? nil : "opaque-task")
    }

    @Test func exactSnapshotHasStableDigestAndRoundTrips() throws {
        let snapshot = request()
        #expect(try snapshot.sha256() == snapshot.sha256())
        let ledger = try GenerationJobLedger(projectID: projectID, jobs: [job(status: .succeeded)]).validated()
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(GenerationJobLedger.self, from: data).validated() == ledger)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.localizedCaseInsensitiveContains("api_key"))
        #expect(!json.localizedCaseInsensitiveContains("authorization"))

        let consentID = UUID()
        let withConsent = GenerationRequestSnapshot(
            prompt: snapshot.prompt, references: snapshot.references,
            parameters: snapshot.parameters, consentRecordIDs: [consentID]
        )
        #expect(try withConsent.sha256() != snapshot.sha256())
    }

    @Test func projectBindingIdentityAndConsentAreValidated() throws {
        let valid = try job(status: .queued)
        #expect(try GenerationJobLedger(projectID: projectID, jobs: [valid]).validated().jobs == [valid])
        var missing = valid
        missing.consentedAt = nil
        #expect(throws: GenerationJobValidationError.missingConsent) {
            try GenerationJobLedger(projectID: projectID, jobs: [missing]).validated()
        }
        #expect(throws: GenerationJobValidationError.projectMismatch) {
            try GenerationJobLedger(projectID: UUID(), jobs: [valid]).validated()
        }
        #expect(throws: GenerationJobValidationError.duplicateJobID) {
            try GenerationJobLedger(projectID: projectID, jobs: [valid, valid]).validated()
        }
    }

    @Test func digestCostAndRelativeReferencesFailClosed() throws {
        let snapshot = request()
        var badDigest = try job()
        badDigest = .init(id: badDigest.id, projectID: projectID, capability: .video, providerID: "mock", modelID: "fixture-v1",
                          target: badDigest.target, request: snapshot, requestSHA256: digest, createdAt: instant, updatedAt: instant)
        #expect(throws: GenerationJobValidationError.invalidDigest) {
            try GenerationJobLedger(projectID: projectID, jobs: [badDigest]).validated()
        }
        let badReference = GenerationRequestSnapshot(prompt: "Shot", references: [
            .init(id: referenceID, kind: "board", relativePath: "../outside.png", sha256: digest, mediaType: "image/png")
        ])
        let referenceJob = GenerationJobRecord(id: jobID, projectID: projectID, capability: .image,
            providerID: "mock", modelID: "fixture", target: .init(kind: .board, id: targetID, sourceRevision: digest),
            request: badReference, requestSHA256: try badReference.sha256(), createdAt: instant, updatedAt: instant)
        #expect(throws: GenerationJobValidationError.invalidReference) {
            try GenerationJobLedger(projectID: projectID, jobs: [referenceJob]).validated()
        }
        var badCost = try job()
        badCost.estimatedCost = .init(currency: "usd", amountMicros: -1)
        #expect(throws: GenerationJobValidationError.invalidCost) {
            try GenerationJobLedger(projectID: projectID, jobs: [badCost]).validated()
        }

        let duplicateID = UUID()
        let duplicateProvenance = GenerationRequestSnapshot(
            prompt: "Shot", consentRecordIDs: [duplicateID, duplicateID]
        )
        let duplicateJob = GenerationJobRecord(
            id: UUID(), projectID: projectID, capability: .image, providerID: "mock", modelID: "fixture",
            target: .init(kind: .board, id: targetID, sourceRevision: digest),
            request: duplicateProvenance, requestSHA256: try duplicateProvenance.sha256(),
            createdAt: instant, updatedAt: instant
        )
        #expect(throws: GenerationJobValidationError.invalidRequest) {
            try GenerationJobLedger(projectID: projectID, jobs: [duplicateJob]).validated()
        }
    }

    @Test func projectSidecarPersistsAtomicallyAndRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("AI/generation-jobs-v1.json")
        let ledger = GenerationJobLedger(projectID: projectID, jobs: [try job(status: .running)])
        try GenerationJobFileStore.write(ledger, to: url)
        #expect(try GenerationJobFileStore.read(from: url) == ledger)
        let permissions = try #require((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)
        #expect(permissions.intValue & 0o077 == 0)

        let link = root.appendingPathComponent("jobs-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: GenerationJobValidationError.invalidFile) { try GenerationJobFileStore.read(from: link) }
    }
}
