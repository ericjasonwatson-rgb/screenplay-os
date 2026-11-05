import Foundation

/// Converts an approved-board brief into a local, unsent job awaiting consent.
/// No image bytes are read or uploaded. A future adapter must validate the
/// referenced media digest and capabilities before presenting exact send bytes.
public enum ProductionImageJobPlanning {
    public enum Failure: Error, Equatable {
        case invalidReference
        case invalidProvider
    }

    public static func awaitingConsent(
        brief: ProductionImageBrief,
        shot: Shot,
        board: BoardFrame,
        approvedBoardIDs: Set<UUID>,
        projectID: UUID,
        jobID: UUID,
        providerID: String,
        modelID: String,
        boardRelativePath: String,
        createdAt: Date
    ) throws -> GenerationJobRecord {
        try ProductionImagePlanning.validateCurrent(
            brief, shot: shot, board: board, approvedBoardIDs: approvedBoardIDs)
        guard !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              providerID.utf8.count <= 200, modelID.utf8.count <= 300 else {
            throw Failure.invalidProvider
        }
        let pathComponents = boardRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !boardRelativePath.isEmpty,
              !boardRelativePath.hasPrefix("/"), !boardRelativePath.hasPrefix("~"),
              !boardRelativePath.contains("\\"), !boardRelativePath.contains("://"),
              !boardRelativePath.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") })
        else { throw Failure.invalidReference }

        let reference = GenerationReference(
            id: brief.selectedBoardImageID, kind: "approved_board",
            relativePath: boardRelativePath,
            sha256: brief.selectedBoardImageSHA256, mediaType: "image/png")
        let request = GenerationRequestSnapshot(
            prompt: brief.promptPreview, references: [reference],
            parameters: ["workflow": "production_image_from_approved_board"])
        let digest = try request.sha256()
        let job = GenerationJobRecord(
            id: jobID, projectID: projectID, capability: .image,
            providerID: providerID, modelID: modelID,
            target: GenerationTarget(kind: .board, id: brief.boardID,
                                     sourceRevision: brief.promptSHA256),
            request: request, requestSHA256: digest, status: .awaitingConsent,
            createdAt: createdAt, updatedAt: createdAt)
        _ = try GenerationJobLedger(projectID: projectID, jobs: [job]).validated()
        return job
    }
}
