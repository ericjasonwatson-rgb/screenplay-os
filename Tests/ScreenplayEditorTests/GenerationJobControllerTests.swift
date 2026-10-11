import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Generation job controller")
struct GenerationJobControllerTests {
    let projectID = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
    let jobID = UUID(uuidString: "52000000-0000-0000-0000-000000000002")!
    let targetID = UUID(uuidString: "53000000-0000-0000-0000-000000000003")!
    let created = Date(timeIntervalSince1970: 1_800_000_000)
    let digest = String(repeating: "a", count: 64)

    func location() -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, root.appendingPathComponent("AI/generation-jobs-v1.json"))
    }

    func job() throws -> GenerationJobRecord {
        let request = GenerationRequestSnapshot(prompt: "Generate the approved shot.")
        return .init(id: jobID, projectID: projectID, capability: .video, providerID: "mock",
                     modelID: "fixture-v1", target: .init(kind: .shot, id: targetID, sourceRevision: digest),
                     request: request, requestSHA256: try request.sha256(), createdAt: created, updatedAt: created)
    }

    @Test func legalTransitionsPersistBeforeTheyAreVisible() async throws {
        let (root, url) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try GenerationJobController(projectID: projectID, storageURL: url)
        try await controller.add(job())
        try await controller.requestConsent(for: jobID, at: created.addingTimeInterval(1))
        try await controller.grantConsent(for: jobID, at: created.addingTimeInterval(2))
        try await controller.markSubmitted(jobID: jobID, at: created.addingTimeInterval(3), providerTaskID: "task-1")
        try await controller.markSucceeded(jobID: jobID, at: created.addingTimeInterval(4),
                                           actualCost: .init(currency: "USD", amountMicros: 100_000))

        let saved = try GenerationJobFileStore.read(from: url)
        let result = try #require(saved.jobs.first)
        #expect(result.status == .succeeded)
        #expect(result.providerTaskID == "task-1")
        #expect(result.actualCost?.amountMicros == 100_000)
    }

    @Test func invalidTransitionsAndCrossProjectJobsFailClosed() async throws {
        let (root, url) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try GenerationJobController(projectID: projectID, storageURL: url)
        try await controller.add(job())
        await #expect(throws: GenerationJobControllerError.invalidTransition) {
            try await controller.grantConsent(for: jobID, at: created)
        }
        let other = try GenerationJobController(projectID: UUID(), storageURL: root.appendingPathComponent("other.json"))
        await #expect(throws: GenerationJobValidationError.projectMismatch) { try await other.add(job()) }
    }

    @Test func relaunchBlocksAmbiguousQueuedSubmissionUntilAcknowledged() async throws {
        let (root, url) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try GenerationJobController(projectID: projectID, storageURL: url)
        try await first.add(job())
        try await first.requestConsent(for: jobID, at: created.addingTimeInterval(1))
        try await first.grantConsent(for: jobID, at: created.addingTimeInterval(2))

        let reopened = try GenerationJobController(projectID: projectID, storageURL: url)
        #expect(await reopened.jobsRequiringRecoveryReview().map(\.id) == [jobID])
        await #expect(throws: GenerationJobControllerError.recoveryReviewRequired) {
            try await reopened.markSubmitted(jobID: jobID, at: created.addingTimeInterval(3))
        }
        try await reopened.acknowledgeRecoveryReview(for: jobID)
        try await reopened.markSubmitted(jobID: jobID, at: created.addingTimeInterval(3))
        #expect(await reopened.snapshot().jobs.first?.status == .running)
    }

    @Test func relaunchPreservesRunningTaskForPollingAndNeverResubmits() async throws {
        let (root, url) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try GenerationJobController(projectID: projectID, storageURL: url)
        try await first.add(job())
        try await first.requestConsent(for: jobID, at: created.addingTimeInterval(1))
        try await first.grantConsent(for: jobID, at: created.addingTimeInterval(2))
        try await first.markSubmitted(jobID: jobID, at: created.addingTimeInterval(3), providerTaskID: "existing-task")

        let reopened = try GenerationJobController(projectID: projectID, storageURL: url)
        let recovered = try #require(await reopened.jobsRequiringRecoveryReview().first)
        #expect(recovered.status == .running)
        #expect(recovered.providerTaskID == "existing-task")
        await #expect(throws: GenerationJobControllerError.recoveryReviewRequired) {
            try await reopened.markSubmitted(jobID: jobID, at: created.addingTimeInterval(4))
        }
    }
}
