import CryptoKit
import Foundation
import ImageIO

/// Bridges an approved storyboard brief to an unselected production-image take.
/// The caller must validate the image with its decoder, store it durably, and
/// obtain explicit consent through the existing generation job workflow first.
/// This pure mapping performs no network request, file write, or project mutation.
public enum ProductionImageTakeHandoff {
    public enum Failure: Error, Equatable {
        case missingOutput
        case invalidOutput
        case invalidProvenance
    }

    public static func candidate(
        brief: ProductionImageBrief,
        currentShot: Shot,
        currentBoard: BoardFrame,
        approvedBoardIDs: Set<UUID>,
        output: Data,
        storedMediaURL: URL,
        takeID: UUID,
        jobID: UUID,
        providerID: String,
        modelID: String,
        generatedAt: Date
    ) throws -> Take {
        try ProductionImagePlanning.validateCurrent(
            brief, shot: currentShot, board: currentBoard,
            approvedBoardIDs: approvedBoardIDs
        )
        guard !output.isEmpty else { throw Failure.missingOutput }
        // Verify a fully decodable PNG and the immutable bytes already written
        // to local storage. A signature-only mock must never become a Take.
        guard output.count <= 20_000_000,
              output.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(output as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              storedMediaURL.isFileURL, !storedMediaURL.path.isEmpty,
              let attributes = try? storedMediaURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let onDisk = try? Data(contentsOf: storedMediaURL),
              onDisk == output
        else { throw Failure.invalidOutput }
        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              providerID.utf8.count <= 200, modelID.utf8.count <= 300
        else { throw Failure.invalidProvenance }

        let digest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
        let provenance = Take.Provenance(
            source: .generationJob,
            generationJobID: jobID,
            providerID: providerID,
            modelID: modelID,
            prompt: brief.promptPreview,
            promptSHA256: brief.promptSHA256,
            referenceAssetPaths: brief.referencePaths,
            generatedAt: generatedAt
        )
        let take = Take(
            id: takeID,
            shotID: brief.shotID,
            boardFrameID: brief.boardID,
            order: currentBoard.imageVersions.count,
            kind: .generatedImage,
            mediaURL: storedMediaURL,
            sha256: digest,
            durationSeconds: brief.durationSeconds,
            status: .candidate,
            note: currentBoard.notes,
            provenance: provenance
        )
        // Validate against the same contract used by persisted take sidecars,
        // but do not write or select anything.
        let sourceRevision = try BoardTakeMigration.sourceRevision([currentBoard])
        _ = try TakeLedger(projectID: UUID(), sourceRevision: sourceRevision, takes: [take]).validated()
        return take
    }
}
