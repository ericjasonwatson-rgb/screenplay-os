import Foundation

/// A media candidate for one stable shot slot. This is a domain projection only;
/// canonical document persistence is deliberately deferred until the package migration exists.
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

        public init(source: Source, generationJobID: UUID? = nil, providerID: String? = nil,
                    modelID: String? = nil, prompt: String? = nil, promptSHA256: String? = nil,
                    referenceAssetPaths: [String] = [], consentRecordIDs: [UUID] = []) {
            self.source = source; self.generationJobID = generationJobID; self.providerID = providerID
            self.modelID = modelID; self.prompt = prompt; self.promptSHA256 = promptSHA256
            self.referenceAssetPaths = referenceAssetPaths; self.consentRecordIDs = consentRecordIDs
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
                guard !image.sha256.isEmpty, !image.fileURL.absoluteString.isEmpty else { throw BoardTakeMigrationError.invalidMedia }
                result.append(Take(
                    id: image.id, shotID: board.shotID, boardFrameID: board.id, order: order,
                    kind: .boardStill, mediaURL: image.fileURL, sha256: image.sha256,
                    durationSeconds: board.durationSeconds,
                    status: image.id == board.selectedImageID ? .selected : .candidate,
                    note: board.notes,
                    provenance: .init(source: .legacyBoardImage, modelID: image.model, prompt: image.prompt)
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
                                  prompt: $0.provenance.prompt ?? "", model: $0.provenance.modelID ?? "")
            }
            result[index].selectedImageID = selected.first?.id
        }
        return result
    }
}
