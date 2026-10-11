import Foundation

/// Complete user-review boundary for one generation request. The app must render
/// every field before Send; approval is valid only while this value still matches
/// the durable job.
public struct GenerationConsentPreview: Codable, Equatable, Identifiable, Sendable {
    public let jobID: UUID
    public let projectID: UUID
    public let capability: GenerationCapability
    public let providerID: String
    public let modelID: String
    public let target: GenerationTarget
    public let request: GenerationRequestSnapshot
    public let requestSHA256: String
    public let estimatedCost: GenerationCost?
    public var id: UUID { jobID }

    public init(job: GenerationJobRecord) {
        jobID = job.id
        projectID = job.projectID
        capability = job.capability
        providerID = job.providerID
        modelID = job.modelID
        target = job.target
        request = job.request
        requestSHA256 = job.requestSHA256
        estimatedCost = job.estimatedCost
    }
}

public struct GenerationActivityEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let capability: GenerationCapability
    public let providerID: String
    public let modelID: String
    public let target: GenerationTarget
    public let request: GenerationRequestSnapshot
    public let requestSHA256: String
    public let status: GenerationJobStatus
    public let consentedAt: Date
    public let submittedAt: Date
    public let completedAt: Date?
    public let estimatedCost: GenerationCost?
    public let actualCost: GenerationCost?
    public let sanitizedError: String?

    fileprivate init(job: GenerationJobRecord, consentedAt: Date, submittedAt: Date) {
        id = job.id
        capability = job.capability
        providerID = job.providerID
        modelID = job.modelID
        target = job.target
        request = job.request
        requestSHA256 = job.requestSHA256
        status = job.status
        self.consentedAt = consentedAt
        self.submittedAt = submittedAt
        completedAt = job.completedAt
        estimatedCost = job.estimatedCost
        actualCost = job.actualCost
        sanitizedError = job.sanitizedError
    }

    enum CodingKeys: String, CodingKey {
        case id, capability, target, request, status
        case providerID = "provider_id"
        case modelID = "model_id"
        case requestSHA256 = "request_sha256"
        case consentedAt = "consented_at"
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case sanitizedError = "sanitized_error"
    }
}

/// User-exported local history. It includes exact creative inputs for
/// accountability, but never transport credentials or provider task IDs.
public struct GenerationActivityExport: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let projectID: UUID
    public let generatedAt: Date
    public let entries: [GenerationActivityEntry]

    public init(ledger: GenerationJobLedger, generatedAt: Date) throws {
        let ledger = try ledger.validated()
        version = Self.currentVersion
        projectID = ledger.projectID
        self.generatedAt = generatedAt
        entries = ledger.jobs.compactMap { job in
            guard let consentedAt = job.consentedAt, let submittedAt = job.submittedAt else { return nil }
            return GenerationActivityEntry(job: job, consentedAt: consentedAt, submittedAt: submittedAt)
        }.sorted { left, right in
            left.submittedAt == right.submittedAt ? left.id.uuidString < right.id.uuidString : left.submittedAt < right.submittedAt
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func write(to url: URL) throws {
        guard url.isFileURL else { throw GenerationJobValidationError.invalidFile }
        let data = try jsonData()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
