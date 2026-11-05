import CryptoKit
import Foundation

/// Local, review-first specification for promoting an approved storyboard
/// into a production-image generation request. No provider or filesystem IO.
public struct ProductionImageBrief: Equatable, Sendable {
    public let shotID: UUID
    public let boardID: UUID
    public let selectedBoardImageID: UUID
    public let selectedBoardImageSHA256: String
    public let selectedBoardImageURL: URL
    public let durationSeconds: Double
    public let directingInstruction: String
    public let styleInstruction: String
    public let referencePaths: [String]
    public let promptPreview: String
    public let promptSHA256: String
}

public enum ProductionImagePlanningError: Error, Equatable {
    case boardNotApproved
    case wrongShot
    case missingSelectedImage
    case invalidSelectedImage
    case invalidDuration
    case invalidInstruction
    case unsafeReference
    case staleBoard
}

public enum ProductionImagePlanning {
    /// The owner explicitly approves board IDs before this promotion stage.
    /// A selected image version alone does not count as creative approval.
    public static func prepare(
        shot: Shot,
        board: BoardFrame,
        approvedBoardIDs: Set<UUID>,
        directingInstruction: String,
        styleInstruction: String = "",
        referencePaths: [String] = []
    ) throws -> ProductionImageBrief {
        guard approvedBoardIDs.contains(board.id) else { throw ProductionImagePlanningError.boardNotApproved }
        guard board.shotID == shot.id && board.sceneSpineID == shot.sceneSpineID else {
            throw ProductionImagePlanningError.wrongShot
        }
        guard let image = board.selectedImage else { throw ProductionImagePlanningError.missingSelectedImage }
        guard image.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              image.fileURL.isFileURL else { throw ProductionImagePlanningError.invalidSelectedImage }
        guard board.durationSeconds.isFinite, board.durationSeconds > 0 else {
            throw ProductionImagePlanningError.invalidDuration
        }
        let instruction = directingInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, instruction.utf8.count <= 12_000,
              styleInstruction.utf8.count <= 12_000 else {
            throw ProductionImagePlanningError.invalidInstruction
        }
        guard referencePaths.count <= 16, Set(referencePaths).count == referencePaths.count,
              referencePaths.allSatisfy(safeRelativePath) else {
            throw ProductionImagePlanningError.unsafeReference
        }
        // These are instructions and metadata only. The referenced board image is
        // NOT attached to an AI request until an adapter explicitly supports and
        // previews those exact image bytes with user consent.
        let preview = """
        Create a production-quality image from the approved storyboard without changing its composition or the intended screen direction.
        Shot: \(shot.label)
        Camera setup: \(shot.setup.rawValue)
        Shot notes: \(shot.notes)
        Board: \(board.label)
        Board notes: \(board.notes)
        Direction: \(instruction)
        Style: \(styleInstruction)
        Approved storyboard image: \(image.id.uuidString) (SHA-256: \(image.sha256))
        Intended shot duration: \(board.durationSeconds) seconds
        Reference paths (local only; no media attached): \(referencePaths.joined(separator: ", "))
        """
        return ProductionImageBrief(
            shotID: shot.id, boardID: board.id,
            selectedBoardImageID: image.id,
            selectedBoardImageSHA256: image.sha256,
            selectedBoardImageURL: image.fileURL,
            durationSeconds: board.durationSeconds,
            directingInstruction: instruction,
            styleInstruction: styleInstruction,
            referencePaths: referencePaths,
            promptPreview: preview,
            promptSHA256: sha256(preview)
        )
    }

    /// Run just before any future request. Any changed board or shot requires
    /// a new preview and approval; no automatic submission or adoption.
    public static func validateCurrent(
        _ brief: ProductionImageBrief,
        shot: Shot,
        board: BoardFrame,
        approvedBoardIDs: Set<UUID>
    ) throws {
        guard approvedBoardIDs.contains(board.id),
              shot.id == brief.shotID, board.id == brief.boardID,
              board.shotID == shot.id, board.sceneSpineID == shot.sceneSpineID,
              board.durationSeconds == brief.durationSeconds,
              let image = board.selectedImage,
              image.id == brief.selectedBoardImageID,
              image.sha256 == brief.selectedBoardImageSHA256,
              image.fileURL == brief.selectedBoardImageURL else {
            throw ProductionImagePlanningError.staleBoard
        }
        // Recomposition detects changes to labels, notes or camera setup too.
        guard let current = try? prepare(
            shot: shot, board: board, approvedBoardIDs: approvedBoardIDs,
            directingInstruction: brief.directingInstruction,
            styleInstruction: brief.styleInstruction,
            referencePaths: brief.referencePaths
        ), current == brief else {
            throw ProductionImagePlanningError.staleBoard
        }
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains("://"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }
    }

    private static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
