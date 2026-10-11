import CryptoKit
import Darwin
import Foundation

public enum GenerationCapability: String, Codable, CaseIterable, Sendable {
    case text, image, video, voice
}

public enum GenerationJobStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case awaitingConsent = "awaiting_consent"
    case queued, running, succeeded, failed, cancelled
}

public enum GenerationTargetKind: String, Codable, CaseIterable, Sendable {
    case dialogueLine = "dialogue_line"
    case board, shot, scene
}

public struct GenerationTarget: Codable, Equatable, Sendable {
    public let kind: GenerationTargetKind
    public let id: UUID
    /// SHA-256 of the project inputs that compose this request.
    public let sourceRevision: String

    public init(kind: GenerationTargetKind, id: UUID, sourceRevision: String) {
        self.kind = kind
        self.id = id
        self.sourceRevision = sourceRevision
    }
}

public struct GenerationReference: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: String
    public let relativePath: String
    public let sha256: String
    public let mediaType: String

    public init(id: UUID, kind: String, relativePath: String, sha256: String, mediaType: String) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.sha256 = sha256
        self.mediaType = mediaType
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case relativePath = "relative_path"
        case sha256
        case mediaType = "media_type"
    }
}

/// Exact creative input approved by the user. Transport-only authentication and
/// headers never belong here; adapters add those after consent.
public struct GenerationRequestSnapshot: Codable, Equatable, Sendable {
    public let prompt: String
    public let references: [GenerationReference]
    public let parameters: [String: String]
    public let continuityEntryIDs: [UUID]
    public let consentRecordIDs: [UUID]

    public init(
        prompt: String,
        references: [GenerationReference] = [],
        parameters: [String: String] = [:],
        continuityEntryIDs: [UUID] = [],
        consentRecordIDs: [UUID] = []
    ) {
        self.prompt = prompt
        self.references = references
        self.parameters = parameters
        self.continuityEntryIDs = continuityEntryIDs
        self.consentRecordIDs = consentRecordIDs
    }

    enum CodingKeys: String, CodingKey {
        case prompt, references, parameters
        case continuityEntryIDs = "continuity_entry_ids"
        case consentRecordIDs = "consent_record_ids"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(String.self, forKey: .prompt)
        references = try container.decodeIfPresent([GenerationReference].self, forKey: .references) ?? []
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        continuityEntryIDs = try container.decodeIfPresent([UUID].self, forKey: .continuityEntryIDs) ?? []
        consentRecordIDs = try container.decodeIfPresent([UUID].self, forKey: .consentRecordIDs) ?? []
    }

    public func sha256() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(self))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Integer micros avoid floating-point drift. nil means the provider price is
/// unknown; it must never be displayed as zero.
public struct GenerationCost: Codable, Equatable, Sendable {
    public let currency: String
    public let amountMicros: Int64

    public init(currency: String, amountMicros: Int64) {
        self.currency = currency
        self.amountMicros = amountMicros
    }

    enum CodingKeys: String, CodingKey {
        case currency
        case amountMicros = "amount_micros"
    }
}

public struct GenerationJobRecord: Codable, Equatable, Identifiable, Sendable {
    public static let recordVersion = 1

    public let version: Int
    public let id: UUID
    public let projectID: UUID
    public let capability: GenerationCapability
    public let providerID: String
    public let modelID: String
    public let target: GenerationTarget
    public let request: GenerationRequestSnapshot
    public let requestSHA256: String
    public var status: GenerationJobStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var consentedAt: Date?
    public var submittedAt: Date?
    public var completedAt: Date?
    public var estimatedCost: GenerationCost?
    public var actualCost: GenerationCost?
    /// Provider messages must be sanitized before assignment.
    public var sanitizedError: String?
    /// Opaque polling identifier. Never used as canonical shot or take identity.
    public var providerTaskID: String?

    public init(
        version: Int = GenerationJobRecord.recordVersion,
        id: UUID,
        projectID: UUID,
        capability: GenerationCapability,
        providerID: String,
        modelID: String,
        target: GenerationTarget,
        request: GenerationRequestSnapshot,
        requestSHA256: String,
        status: GenerationJobStatus = .draft,
        createdAt: Date,
        updatedAt: Date,
        consentedAt: Date? = nil,
        submittedAt: Date? = nil,
        completedAt: Date? = nil,
        estimatedCost: GenerationCost? = nil,
        actualCost: GenerationCost? = nil,
        sanitizedError: String? = nil,
        providerTaskID: String? = nil
    ) {
        self.version = version
        self.id = id
        self.projectID = projectID
        self.capability = capability
        self.providerID = providerID
        self.modelID = modelID
        self.target = target
        self.request = request
        self.requestSHA256 = requestSHA256
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.consentedAt = consentedAt
        self.submittedAt = submittedAt
        self.completedAt = completedAt
        self.estimatedCost = estimatedCost
        self.actualCost = actualCost
        self.sanitizedError = sanitizedError
        self.providerTaskID = providerTaskID
    }

    enum CodingKeys: String, CodingKey {
        case version, id, capability, target, request, status
        case projectID = "project_id"
        case providerID = "provider_id"
        case modelID = "model_id"
        case requestSHA256 = "request_sha256"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case consentedAt = "consented_at"
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case sanitizedError = "sanitized_error"
        case providerTaskID = "provider_task_id"
    }
}

public struct GenerationJobLedger: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let projectID: UUID
    public var jobs: [GenerationJobRecord]

    public init(version: Int = GenerationJobLedger.currentVersion, projectID: UUID, jobs: [GenerationJobRecord] = []) {
        self.version = version
        self.projectID = projectID
        self.jobs = jobs
    }

    enum CodingKeys: String, CodingKey {
        case version, jobs
        case projectID = "project_id"
    }

    public func validated() throws -> GenerationJobLedger {
        guard version == Self.currentVersion else { throw GenerationJobValidationError.unsupportedLedgerVersion }
        guard Set(jobs.map(\.id)).count == jobs.count else { throw GenerationJobValidationError.duplicateJobID }
        for job in jobs {
            guard job.version == GenerationJobRecord.recordVersion else { throw GenerationJobValidationError.unsupportedRecordVersion }
            guard job.projectID == projectID else { throw GenerationJobValidationError.projectMismatch }
            guard Self.nonempty(job.providerID, maximum: 200), Self.nonempty(job.modelID, maximum: 300) else {
                throw GenerationJobValidationError.invalidProvider
            }
            guard Self.hexDigest(job.target.sourceRevision), Self.hexDigest(job.requestSHA256),
                  job.requestSHA256 == (try job.request.sha256()) else { throw GenerationJobValidationError.invalidDigest }
            guard Self.nonempty(job.request.prompt, maximum: 1_000_000), job.request.references.count <= 64,
                  job.request.parameters.count <= 128,
                  job.request.continuityEntryIDs.count <= 10_000,
                  job.request.consentRecordIDs.count <= 10_000,
                  Set(job.request.continuityEntryIDs).count == job.request.continuityEntryIDs.count,
                  Set(job.request.consentRecordIDs).count == job.request.consentRecordIDs.count else {
                throw GenerationJobValidationError.invalidRequest
            }
            for (key, value) in job.request.parameters where !Self.nonempty(key, maximum: 200) || value.utf8.count > 20_000 {
                throw GenerationJobValidationError.invalidRequest
            }
            var referenceIDs: Set<UUID> = []
            for reference in job.request.references {
                guard referenceIDs.insert(reference.id).inserted,
                      Self.nonempty(reference.kind, maximum: 100), Self.nonempty(reference.mediaType, maximum: 200),
                      Self.safeRelativePath(reference.relativePath), Self.hexDigest(reference.sha256) else {
                    throw GenerationJobValidationError.invalidReference
                }
            }
            for cost in [job.estimatedCost, job.actualCost].compactMap({ $0 }) {
                guard cost.amountMicros >= 0, cost.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
                    throw GenerationJobValidationError.invalidCost
                }
            }
            guard job.updatedAt >= job.createdAt,
                  job.consentedAt.map({ $0 >= job.createdAt && $0 <= job.updatedAt }) ?? true,
                  job.submittedAt.map({ $0 >= job.createdAt && $0 <= job.updatedAt }) ?? true,
                  job.completedAt.map({ $0 >= job.createdAt && $0 <= job.updatedAt }) ?? true else {
                throw GenerationJobValidationError.invalidTimestamps
            }
            if [.queued, .running, .succeeded, .failed].contains(job.status), job.consentedAt == nil {
                throw GenerationJobValidationError.missingConsent
            }
            if [.running, .succeeded, .failed].contains(job.status), job.submittedAt == nil {
                throw GenerationJobValidationError.missingSubmission
            }
            if [.succeeded, .failed].contains(job.status), job.completedAt == nil {
                throw GenerationJobValidationError.missingCompletion
            }
            if job.status == .failed, !Self.nonempty(job.sanitizedError ?? "", maximum: 4_000) {
                throw GenerationJobValidationError.missingFailure
            }
            if let value = job.providerTaskID, !Self.nonempty(value, maximum: 1_000) {
                throw GenerationJobValidationError.invalidRequest
            }
        }
        return self
    }

    private static func nonempty(_ value: String, maximum: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && value.utf8.count <= maximum
    }
    private static func hexDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
    private static func safeRelativePath(_ value: String) -> Bool {
        guard nonempty(value, maximum: 4_096), !value.hasPrefix("/"), !value.hasPrefix("~") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}

public enum GenerationJobValidationError: Error, Equatable {
    case unsupportedLedgerVersion, unsupportedRecordVersion, duplicateJobID, projectMismatch
    case invalidProvider, invalidDigest, invalidRequest, invalidReference, invalidCost, invalidTimestamps
    case missingConsent, missingSubmission, missingCompletion, missingFailure, invalidFile
}

/// Local sidecar persistence. The caller chooses a project-bound location; this
/// type never writes credentials or modifies the canonical screenplay document.
public enum GenerationJobFileStore {
    public static let maximumBytes = 50 * 1024 * 1024

    public static func write(_ ledger: GenerationJobLedger, to url: URL) throws {
        guard url.isFileURL else { throw GenerationJobValidationError.invalidFile }
        let validated = try ledger.validated()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(validated)
        guard data.count <= maximumBytes else { throw GenerationJobValidationError.invalidFile }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL) throws -> GenerationJobLedger {
        guard url.isFileURL else { throw GenerationJobValidationError.invalidFile }
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size <= maximumBytes else { throw GenerationJobValidationError.invalidFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GenerationJobLedger.self, from: Data(contentsOf: url)).validated()
    }
}
