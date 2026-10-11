import Foundation

public enum GenerationJobControllerError: Error, Equatable {
    case jobNotFound
    case duplicateJobID
    case invalidTransition
    case recoveryReviewRequired
    case consentPreviewChanged
}

/// Serializes durable job changes and persists each accepted transition before
/// exposing it. Network adapters remain outside this actor.
public actor GenerationJobController {
    public let projectID: UUID
    public let storageURL: URL

    private var ledger: GenerationJobLedger
    /// Queued/running jobs found on launch are ambiguous. They remain blocked
    /// until a user-directed reconciliation explicitly acknowledges them.
    private var recoveryReviewIDs: Set<UUID>

    public init(projectID: UUID, storageURL: URL) throws {
        self.projectID = projectID
        self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let loaded = try GenerationJobFileStore.read(from: storageURL)
            guard loaded.projectID == projectID else { throw GenerationJobValidationError.projectMismatch }
            ledger = loaded
        } else {
            ledger = GenerationJobLedger(projectID: projectID)
        }
        recoveryReviewIDs = Set(ledger.jobs.lazy.filter { [.queued, .running].contains($0.status) }.map(\.id))
    }

    public func snapshot() -> GenerationJobLedger { ledger }

    public func jobsRequiringRecoveryReview() -> [GenerationJobRecord] {
        ledger.jobs.filter { recoveryReviewIDs.contains($0.id) }
    }

    public func add(_ job: GenerationJobRecord) throws {
        guard job.projectID == projectID else { throw GenerationJobValidationError.projectMismatch }
        guard !ledger.jobs.contains(where: { $0.id == job.id }) else { throw GenerationJobControllerError.duplicateJobID }
        var candidate = ledger
        candidate.jobs.append(job)
        try commit(candidate)
    }

    public func requestConsent(for jobID: UUID, at date: Date) throws {
        try update(jobID) { job in
            guard job.status == .draft else { throw GenerationJobControllerError.invalidTransition }
            job.status = .awaitingConsent
            job.updatedAt = date
        }
    }

    public func consentPreview(for jobID: UUID) throws -> GenerationConsentPreview {
        guard let job = ledger.jobs.first(where: { $0.id == jobID }) else {
            throw GenerationJobControllerError.jobNotFound
        }
        guard [.draft, .awaitingConsent].contains(job.status) else {
            throw GenerationJobControllerError.invalidTransition
        }
        return GenerationConsentPreview(job: job)
    }

    public func grantConsent(for jobID: UUID, matching preview: GenerationConsentPreview, at date: Date) throws {
        try update(jobID) { job in
            guard job.status == .awaitingConsent else { throw GenerationJobControllerError.invalidTransition }
            guard preview == GenerationConsentPreview(job: job) else {
                throw GenerationJobControllerError.consentPreviewChanged
            }
            job.status = .queued
            job.consentedAt = date
            job.updatedAt = date
        }
    }

    /// Call only from an explicit send action. A recovered job must first be
    /// acknowledged; relaunch itself never invokes this method.
    public func markSubmitted(jobID: UUID, at date: Date, providerTaskID: String? = nil) throws {
        guard !recoveryReviewIDs.contains(jobID) else { throw GenerationJobControllerError.recoveryReviewRequired }
        try update(jobID) { job in
            guard job.status == .queued else { throw GenerationJobControllerError.invalidTransition }
            job.status = .running
            job.submittedAt = date
            job.updatedAt = date
            job.providerTaskID = providerTaskID
        }
    }

    public func markSucceeded(jobID: UUID, at date: Date, actualCost: GenerationCost? = nil) throws {
        try finish(jobID: jobID, status: .succeeded, at: date, actualCost: actualCost, error: nil)
    }

    public func markFailed(jobID: UUID, at date: Date, sanitizedError: String, actualCost: GenerationCost? = nil) throws {
        try finish(jobID: jobID, status: .failed, at: date, actualCost: actualCost, error: sanitizedError)
    }

    public func cancel(jobID: UUID, at date: Date) throws {
        try update(jobID) { job in
            guard [.draft, .awaitingConsent, .queued, .running].contains(job.status) else {
                throw GenerationJobControllerError.invalidTransition
            }
            job.status = .cancelled
            job.updatedAt = date
            job.completedAt = date
        }
        recoveryReviewIDs.remove(jobID)
    }

    /// Records an explicit user decision that the caller may either poll an
    /// existing provider task or submit a previously queued request. It performs
    /// no network work and never changes the persisted provider state.
    public func acknowledgeRecoveryReview(for jobID: UUID) throws {
        guard recoveryReviewIDs.remove(jobID) != nil else {
            throw GenerationJobControllerError.invalidTransition
        }
    }

    public func activityExport(generatedAt: Date) throws -> GenerationActivityExport {
        try GenerationActivityExport(ledger: ledger, generatedAt: generatedAt)
    }

    public func costLedger() throws -> GenerationCostLedger {
        try GenerationCostLedger(ledger: ledger)
    }

    private func finish(jobID: UUID, status: GenerationJobStatus, at date: Date,
                        actualCost: GenerationCost?, error: String?) throws {
        try update(jobID) { job in
            guard job.status == .running else { throw GenerationJobControllerError.invalidTransition }
            job.status = status
            job.updatedAt = date
            job.completedAt = date
            job.actualCost = actualCost
            job.sanitizedError = error
        }
        recoveryReviewIDs.remove(jobID)
    }

    private func update(_ jobID: UUID, change: (inout GenerationJobRecord) throws -> Void) throws {
        guard let index = ledger.jobs.firstIndex(where: { $0.id == jobID }) else {
            throw GenerationJobControllerError.jobNotFound
        }
        var candidate = ledger
        try change(&candidate.jobs[index])
        try commit(candidate)
    }

    private func commit(_ candidate: GenerationJobLedger) throws {
        let validated = try candidate.validated()
        try GenerationJobFileStore.write(validated, to: storageURL)
        ledger = validated
    }
}
