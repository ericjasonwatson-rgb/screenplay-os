import CryptoKit
import Foundation

/// A media candidate for one stable shot slot. Canonical document persistence is
/// deliberately deferred until the package migration exists; TakeLedger is a
/// project-bound local sidecar in the interim.
public struct Take: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case boardStill = "board_still"
        case generatedImage = "generated_image"
        case generatedVideo = "generated_video"
        case filmedClip = "filmed_clip"
        case voice
    }

    public enum Status: String, Codable, Sendable {
        case candidate
        case selected
        case rejected
    }

    public struct Provenance: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable { case legacyBoardImage = "legacy_board_image", generationJob = "generation_job", localImport = "local_import" }
        public var source: Source
        public var generationJobID: UUID?
        public var providerID: String?
        public var modelID: String?
        public var prompt: String?
        public var promptSHA256: String?
        public var referenceAssetPaths: [String]
        public var consentRecordIDs: [UUID]
        public var generatedAt: Date?
        public var estimatedCost: GenerationCost?
        public var actualCost: GenerationCost?

        public init(source: Source, generationJobID: UUID? = nil, providerID: String? = nil,
                    modelID: String? = nil, prompt: String? = nil, promptSHA256: String? = nil,
                    referenceAssetPaths: [String] = [], consentRecordIDs: [UUID] = [],
                    generatedAt: Date? = nil, estimatedCost: GenerationCost? = nil,
                    actualCost: GenerationCost? = nil) {
            self.source = source; self.generationJobID = generationJobID; self.providerID = providerID
            self.modelID = modelID; self.prompt = prompt; self.promptSHA256 = promptSHA256
            self.referenceAssetPaths = referenceAssetPaths; self.consentRecordIDs = consentRecordIDs
            self.generatedAt = generatedAt; self.estimatedCost = estimatedCost; self.actualCost = actualCost
        }
    }

    public var id: UUID
    public var shotID: UUID
    public var boardFrameID: UUID?
    public var order: Int
    public var kind: Kind
    public var mediaURL: URL
    public var sha256: String
    public var durationSeconds: Double
    public var inPointSeconds: Double
    public var outPointSeconds: Double
    public var status: Status
    public var note: String
    public var provenance: Provenance

    public init(id: UUID = UUID(), shotID: UUID, boardFrameID: UUID? = nil, order: Int = 0,
                kind: Kind, mediaURL: URL, sha256: String, durationSeconds: Double,
                inPointSeconds: Double = 0, outPointSeconds: Double? = nil,
                status: Status = .candidate, note: String = "", provenance: Provenance) {
        self.id = id; self.shotID = shotID; self.boardFrameID = boardFrameID; self.order = order
        self.kind = kind; self.mediaURL = mediaURL; self.sha256 = sha256
        self.durationSeconds = durationSeconds; self.inPointSeconds = inPointSeconds
        self.outPointSeconds = outPointSeconds ?? durationSeconds; self.status = status
        self.note = note; self.provenance = provenance
    }
}

public struct TakeLedger: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let projectID: UUID
    /// Digest of the document inputs from which this snapshot was built. A nil
    /// value is valid only for an empty ledger.
    public var sourceRevision: String?
    public var takes: [Take]

    public init(version: Int = TakeLedger.currentVersion, projectID: UUID,
                sourceRevision: String? = nil, takes: [Take] = []) {
        self.version = version
        self.projectID = projectID
        self.sourceRevision = sourceRevision
        self.takes = takes
    }

    enum CodingKeys: String, CodingKey {
        case version, takes
        case projectID = "project_id"
        case sourceRevision = "source_revision"
    }

    public func validated() throws -> TakeLedger {
        guard version == Self.currentVersion else { throw TakeValidationError.unsupportedLedgerVersion }
        guard Set(takes.map(\.id)).count == takes.count else { throw TakeValidationError.duplicateTakeID }
        if takes.isEmpty {
            guard sourceRevision == nil || Self.hexDigest(sourceRevision!) else { throw TakeValidationError.invalidDigest }
        } else {
            guard sourceRevision.map(Self.hexDigest) == true else { throw TakeValidationError.invalidDigest }
        }

        var selectedTargets: Set<String> = []
        for take in takes {
            guard take.order >= 0 else { throw TakeValidationError.invalidOrder }
            guard Self.validMediaURL(take.mediaURL), Self.hexDigest(take.sha256) else {
                throw TakeValidationError.invalidMedia
            }
            guard take.durationSeconds.isFinite, take.durationSeconds > 0,
                  take.inPointSeconds.isFinite, take.inPointSeconds >= 0,
                  take.outPointSeconds.isFinite, take.outPointSeconds > take.inPointSeconds,
                  take.outPointSeconds <= take.durationSeconds else { throw TakeValidationError.invalidTiming }
            guard take.note.utf8.count <= 100_000 else { throw TakeValidationError.invalidText }
            let provenance = take.provenance
            guard provenance.providerID.map({ Self.nonempty($0, maximum: 200) }) ?? true,
                  provenance.modelID.map({ Self.nonempty($0, maximum: 300) }) ?? true,
                  provenance.prompt.map({ $0.utf8.count <= 1_000_000 }) ?? true,
                  provenance.promptSHA256.map(Self.hexDigest) ?? true,
                  provenance.referenceAssetPaths.count <= 64,
                  provenance.consentRecordIDs.count <= 10_000,
                  Set(provenance.referenceAssetPaths).count == provenance.referenceAssetPaths.count,
                  Set(provenance.consentRecordIDs).count == provenance.consentRecordIDs.count,
                  provenance.referenceAssetPaths.allSatisfy(Self.safeRelativePath) else {
                throw TakeValidationError.invalidProvenance
            }
            if provenance.source == .generationJob {
                guard provenance.generationJobID != nil,
                      provenance.providerID != nil, provenance.modelID != nil,
                      let prompt = provenance.prompt, let promptSHA256 = provenance.promptSHA256,
                      Self.sha256(prompt) == promptSHA256,
                      provenance.generatedAt != nil else { throw TakeValidationError.invalidProvenance }
            }
            for cost in [provenance.estimatedCost, provenance.actualCost].compactMap({ $0 }) {
                guard cost.amountMicros >= 0,
                      cost.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
                    throw TakeValidationError.invalidProvenance
                }
            }
            if take.status == .selected {
                let target = Self.targetKey(for: take)
                guard selectedTargets.insert(target).inserted else { throw TakeValidationError.multipleSelectedTakes }
            }
        }
        return self
    }

    private static func nonempty(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
    }
    private static func hexDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func targetKey(for take: Take) -> String {
        take.boardFrameID.map { "board:\($0.uuidString)" } ?? "shot:\(take.shotID.uuidString)"
    }
    private static func safeRelativePath(_ value: String) -> Bool {
        guard nonempty(value, maximum: 4_096), !value.hasPrefix("/"), !value.hasPrefix("~") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    private static func validMediaURL(_ url: URL) -> Bool {
        let value = url.absoluteString
        guard !value.isEmpty, value.utf8.count <= 8_192 else { return false }
        if url.isFileURL { return !url.path.isEmpty && url.path.utf8.count <= 4_096 }
        guard url.scheme == nil, url.host == nil else { return false }
        return safeRelativePath(url.path.removingPercentEncoding ?? url.path)
    }
}

public enum TakeValidationError: Error, Equatable {
    case unsupportedLedgerVersion, duplicateTakeID, projectMismatch, invalidDigest
    case invalidOrder, invalidMedia, invalidTiming, invalidText, invalidProvenance
    case multipleSelectedTakes, takeNotFound, invalidFile
}

public enum TakeFileStore {
    public static let maximumBytes = 50 * 1_024 * 1_024

    public static func write(_ ledger: TakeLedger, to url: URL) throws {
        guard url.isFileURL else { throw TakeValidationError.invalidFile }
        try validateWriteDestination(url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(ledger.validated())
        guard data.count <= maximumBytes else { throw TakeValidationError.invalidFile }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func read(from url: URL) throws -> TakeLedger {
        guard url.isFileURL else { throw TakeValidationError.invalidFile }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else { throw TakeValidationError.invalidFile }
        return try JSONDecoder().decode(TakeLedger.self, from: Data(contentsOf: url)).validated()
    }

    private static func validateWriteDestination(_ url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw TakeValidationError.invalidFile
            }
        }
        var existingParent = url.deletingLastPathComponent()
        while !manager.fileExists(atPath: existingParent.path) {
            let next = existingParent.deletingLastPathComponent()
            guard next.path != existingParent.path else { throw TakeValidationError.invalidFile }
            existingParent = next
        }
        let parentValues = try existingParent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw TakeValidationError.invalidFile
        }
    }
}

/// Serializes local take-sidecar changes. Every accepted mutation reaches disk
/// before the new snapshot becomes visible to callers.
public actor TakeController {
    public let projectID: UUID
    public let storageURL: URL
    private var ledger: TakeLedger

    public init(projectID: UUID, storageURL: URL) throws {
        self.projectID = projectID
        self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let loaded = try TakeFileStore.read(from: storageURL)
            guard loaded.projectID == projectID else { throw TakeValidationError.projectMismatch }
            ledger = loaded
        } else {
            ledger = TakeLedger(projectID: projectID)
        }
    }

    public func snapshot() -> TakeLedger { ledger }

    public func replaceAll(with takes: [Take], sourceRevision: String) throws {
        try commit(TakeLedger(projectID: projectID, sourceRevision: sourceRevision, takes: takes))
    }

    public func select(_ takeID: UUID) throws {
        guard let selected = ledger.takes.first(where: { $0.id == takeID }) else { throw TakeValidationError.takeNotFound }
        let target = targetKey(for: selected)
        var candidate = ledger
        for index in candidate.takes.indices {
            let otherTarget = targetKey(for: candidate.takes[index])
            if otherTarget == target, candidate.takes[index].status == .selected {
                candidate.takes[index].status = .candidate
            }
        }
        guard let index = candidate.takes.firstIndex(where: { $0.id == takeID }) else { throw TakeValidationError.takeNotFound }
        candidate.takes[index].status = .selected
        try commit(candidate)
    }

    public func reject(_ takeID: UUID) throws {
        guard let index = ledger.takes.firstIndex(where: { $0.id == takeID }) else { throw TakeValidationError.takeNotFound }
        var candidate = ledger
        candidate.takes[index].status = .rejected
        try commit(candidate)
    }

    private func commit(_ candidate: TakeLedger) throws {
        let validated = try candidate.validated()
        try TakeFileStore.write(validated, to: storageURL)
        ledger = validated
    }

    private func targetKey(for take: Take) -> String {
        take.boardFrameID.map { "board:\($0.uuidString)" } ?? "shot:\(take.shotID.uuidString)"
    }
}

public enum BoardTakeMigrationError: Error, Equatable {
    case invalidDuration
    case duplicateTakeID
    case missingSelectedImage
    case missingBoardFrame
    case wrongShot
    case unsupportedTakeKind
    case multipleSelectedTakes
    case invalidMedia
}

/// Lossless, deterministic bridge for the existing BoardImageVersion records.
/// It does not write a new schema or delete the legacy records.
public enum BoardTakeMigration {
    public static func sourceRevision(_ boards: [BoardFrame]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(boards)).map { String(format: "%02x", $0) }.joined()
    }

    public static func project(_ boards: [BoardFrame]) throws -> [Take] {
        var ids: Set<UUID> = []
        var result: [Take] = []
        for board in boards {
            guard board.durationSeconds.isFinite, board.durationSeconds > 0 else { throw BoardTakeMigrationError.invalidDuration }
            if let selected = board.selectedImageID,
               !board.imageVersions.contains(where: { $0.id == selected }) {
                throw BoardTakeMigrationError.missingSelectedImage
            }
            for (order, image) in board.imageVersions.enumerated() {
                guard ids.insert(image.id).inserted else { throw BoardTakeMigrationError.duplicateTakeID }
                // Older documents only required a nonempty digest field. Preserve
                // those records in the lossless projection; the stricter TakeLedger
                // correctly refuses to persist them until the media is revalidated.
                guard !image.sha256.isEmpty, !image.fileURL.absoluteString.isEmpty else {
                    throw BoardTakeMigrationError.invalidMedia
                }
                let generated = image.generationJobID != nil
                let imported = !generated && image.importedAt != nil
                result.append(Take(
                    id: image.id, shotID: board.shotID, boardFrameID: board.id, order: order,
                    kind: generated ? .generatedImage : .boardStill,
                    mediaURL: image.fileURL, sha256: image.sha256,
                    durationSeconds: board.durationSeconds,
                    status: image.id == board.selectedImageID ? .selected : .candidate,
                    note: board.notes,
                    provenance: .init(
                        source: generated ? .generationJob : (imported ? .localImport : .legacyBoardImage),
                        generationJobID: image.generationJobID, providerID: image.providerID,
                        modelID: image.model, prompt: image.prompt,
                        promptSHA256: generated ? sha256(image.prompt) : nil,
                        generatedAt: image.generatedAt ?? image.importedAt,
                        estimatedCost: image.estimatedCost,
                        actualCost: image.actualCost
                    )
                ))
            }
        }
        return result
    }

    public static func applyingImageTakes(_ takes: [Take], to boards: [BoardFrame]) throws -> [BoardFrame] {
        var result = boards
        let grouped = Dictionary(grouping: takes, by: \Take.boardFrameID)
        guard grouped[nil] == nil else { throw BoardTakeMigrationError.missingBoardFrame }
        for (frameID, group) in grouped {
            guard let frameID, let index = result.firstIndex(where: { $0.id == frameID }) else {
                throw BoardTakeMigrationError.missingBoardFrame
            }
            guard group.allSatisfy({ $0.shotID == result[index].shotID }) else { throw BoardTakeMigrationError.wrongShot }
            guard group.allSatisfy({ $0.kind == .boardStill || $0.kind == .generatedImage }) else {
                throw BoardTakeMigrationError.unsupportedTakeKind
            }
            let selected = group.filter { $0.status == .selected }
            guard selected.count <= 1 else { throw BoardTakeMigrationError.multipleSelectedTakes }
            let ordered = group.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
            result[index].imageVersions = ordered.map {
                BoardImageVersion(id: $0.id, fileURL: $0.mediaURL, sha256: $0.sha256,
                                  prompt: $0.provenance.prompt ?? "", model: $0.provenance.modelID ?? "",
                                  providerID: $0.provenance.providerID,
                                  generationJobID: $0.provenance.generationJobID,
                                  generatedAt: $0.provenance.source == .generationJob ? $0.provenance.generatedAt : nil,
                                  importedAt: $0.provenance.source == .localImport ? $0.provenance.generatedAt : nil,
                                  estimatedCost: $0.provenance.estimatedCost,
                                  actualCost: $0.provenance.actualCost)
            }
            result[index].selectedImageID = selected.first?.id
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
