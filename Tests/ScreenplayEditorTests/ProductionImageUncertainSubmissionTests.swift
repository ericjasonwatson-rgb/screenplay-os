import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Uncertain image submission recovery policy")
struct ProductionImageUncertainSubmissionTests {
    private func job(status: GenerationJobStatus, submitted: Bool) throws -> GenerationJobRecord {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = GenerationRequestSnapshot(
            prompt: "Preserve approved board composition",
            parameters: ["workflow": "production_image_from_approved_board"])
        return GenerationJobRecord(
            id: UUID(), projectID: UUID(), capability: .image,
            providerID: "openai", modelID: "gpt-image-1.5",
            target: GenerationTarget(kind: .board, id: UUID(),
                sourceRevision: String(repeating: "a", count: 64)),
            request: request, requestSHA256: try request.sha256(),
            status: status, createdAt: now, updatedAt: now,
            consentedAt: [.queued, .running, .succeeded].contains(status) ? now : nil,
            submittedAt: submitted ? now.addingTimeInterval(1) : nil,
            completedAt: status == .succeeded ? now.addingTimeInterval(2) : nil)
    }

    @Test func submittedRunningWithoutSavedResultIsUnresolved() throws {
        let running = try job(status: .running, submitted: true)
        #expect(ProductionImageUncertainSubmission.isUnresolved(
            running, hasPreservedImage: false))
        #expect(!ProductionImageUncertainSubmission.isUnresolved(
            running, hasPreservedImage: true))
        #expect(ProductionImageUncertainSubmission.guidance.contains("will not retry"))
        #expect(ProductionImageUncertainSubmission.guidance.contains("charge"))
    }

    @Test func queuedAndCompletedJobsAreNotUncertainSubmissions() throws {
        #expect(!ProductionImageUncertainSubmission.isUnresolved(
            try job(status: .queued, submitted: false), hasPreservedImage: false))
        #expect(!ProductionImageUncertainSubmission.isUnresolved(
            try job(status: .awaitingConsent, submitted: false), hasPreservedImage: false))
        #expect(!ProductionImageUncertainSubmission.isUnresolved(
            try job(status: .succeeded, submitted: true), hasPreservedImage: false))
    }

    @Test func classificationCannotChangeJobStateOrCauseNetworkWork() throws {
        let running = try job(status: .running, submitted: true)
        let before = running
        _ = ProductionImageUncertainSubmission.isUnresolved(
            running, hasPreservedImage: false)
        #expect(running == before)
        #expect(running.status == .running)
        #expect(running.submittedAt != nil)
        #expect(running.completedAt == nil)
    }
}
