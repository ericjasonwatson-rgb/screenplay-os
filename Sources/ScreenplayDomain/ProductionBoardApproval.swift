import CryptoKit
import Foundation

/// A local approval of one exact board/shot revision. Not a reusable permission
/// to transmit creative work: every network send still requires its own consent.
public struct ProductionBoardApproval: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let projectID: UUID
    public let shotID: UUID
    public let boardID: UUID
    public let selectedImageID: UUID
    public let selectedImageSHA256: String
    public let boardRevisionSHA256: String
    public let approvedAt: Date
}

public enum ProductionBoardApprovalError: Error, Equatable {
    case missingSelection
    case wrongShot
    case changedSource
    case invalidRecord
    case invalidFile
}

public enum ProductionBoardApprovals {
    private struct Source: Encodable {
        let shot: Shot
        let board: BoardFrame
    }

    private static func revision(shot: Shot, board: BoardFrame) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(Source(shot: shot, board: board))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public static func approve(projectID: UUID, shot: Shot, board: BoardFrame,
                               approvalID: UUID = UUID(), approvedAt: Date = Date()) throws -> ProductionBoardApproval {
        guard shot.id == board.shotID && shot.sceneSpineID == board.sceneSpineID else {
            throw ProductionBoardApprovalError.wrongShot
        }
        guard let selected = board.selectedImage,
              selected.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { throw ProductionBoardApprovalError.missingSelection }
        return ProductionBoardApproval(
            version: 1, id: approvalID, projectID: projectID,
            shotID: shot.id, boardID: board.id, selectedImageID: selected.id,
            selectedImageSHA256: selected.sha256,
            boardRevisionSHA256: try revision(shot: shot, board: board),
            approvedAt: approvedAt)
    }

    public static func validate(_ record: ProductionBoardApproval, projectID: UUID,
                                shot: Shot, board: BoardFrame) throws {
        guard record.version == 1, record.projectID == projectID else {
            throw ProductionBoardApprovalError.invalidRecord
        }
        guard record.shotID == shot.id, record.boardID == board.id,
              shot.id == board.shotID, shot.sceneSpineID == board.sceneSpineID,
              let selected = board.selectedImage,
              selected.id == record.selectedImageID,
              selected.sha256 == record.selectedImageSHA256,
              try revision(shot: shot, board: board) == record.boardRevisionSHA256 else {
            throw ProductionBoardApprovalError.changedSource
        }
    }

    /// A local draft-sidecar, not the released portable project package.
    public static func store(_ record: ProductionBoardApproval, at destination: URL) throws {
        guard destination.isFileURL else { throw ProductionBoardApprovalError.invalidFile }
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let parentInfo = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parentInfo.isDirectory == true && parentInfo.isSymbolicLink != true else {
            throw ProductionBoardApprovalError.invalidFile
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let info = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true && info.isSymbolicLink != true else {
                throw ProductionBoardApprovalError.invalidFile
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= 16_384 else { throw ProductionBoardApprovalError.invalidFile }
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    public static func load(at location: URL) throws -> ProductionBoardApproval {
        guard location.isFileURL else { throw ProductionBoardApprovalError.invalidFile }
        let info = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true && info.isSymbolicLink != true,
              let size = info.fileSize, size > 0 && size <= 16_384 else {
            throw ProductionBoardApprovalError.invalidFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ProductionBoardApproval.self, from: Data(contentsOf: location))
        guard record.version == 1 else { throw ProductionBoardApprovalError.invalidRecord }
        return record
    }
}
