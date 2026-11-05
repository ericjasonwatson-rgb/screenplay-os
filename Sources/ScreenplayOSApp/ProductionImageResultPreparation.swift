import Foundation
import ScreenplayDomain

/// Offline validation of a single image returned by the Images Edit endpoint.
/// No network access, file writes, project mutations or provider billing.
enum OpenAIReferenceImageResponse {
    enum Failure: Error, Equatable {
        case oversizedResponse
        case invalidEnvelope
        case missingImage
        case unsupportedFormat
        case invalidImage
    }

    static let maximumResponseBytes = 30_000_000
    static let maximumImageBytes = 20_000_000

    /// Only a single Base64 PNG is accepted. URLs and revised prompts are never
    /// silently treated as approved images.
    static func decode(_ response: Data) throws -> Data {
        guard response.count > 0, response.count <= maximumResponseBytes else {
            throw Failure.oversizedResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let records = json["data"] as? [[String: Any]],
              records.count == 1 else {
            throw Failure.invalidEnvelope
        }
        let record = records[0]
        guard record["url"] == nil, record["revised_prompt"] == nil,
              let encoded = record["b64_json"] as? String,
              !encoded.isEmpty else {
            throw Failure.missingImage
        }
        // Avoid Base64 expanding into unbounded memory.
        guard encoded.utf8.count <= 4 * ((maximumImageBytes + 2) / 3) else {
            throw Failure.oversizedResponse
        }
        guard let bytes = Data(base64Encoded: encoded) else {
            throw Failure.invalidEnvelope
        }
        guard bytes.count <= maximumImageBytes,
              bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw Failure.unsupportedFormat
        }
        guard BoardImageAPI.validPNG(bytes) else { throw Failure.invalidImage }
        return bytes
    }
}

/// Complete local candidate preparation after a separately completed,
/// consented provider job. The caller remains responsible for inserting a Take
/// into the project and enabling Undo, neither of which happens here.
enum ProductionImageResultPreparation {
    enum Failure: Error, Equatable {
        case jobNotCompleted
        case mismatchedJob
    }

    static func prepare(
        response: Data,
        job: GenerationJobRecord,
        staged: ApprovedProductionImageReview,
        currentShot: Shot,
        currentBoard: BoardFrame,
        approval: ProductionBoardApproval,
        documentURL: URL,
        takeID: UUID,
        now: Date
    ) throws -> Take {
        guard job.status == .succeeded, job.consentedAt != nil,
              job.submittedAt != nil, job.completedAt != nil else {
            throw Failure.jobNotCompleted
        }
        guard job.id == staged.job.id, job.projectID == approval.projectID,
              job.capability == .image, job.target.kind == .board,
              job.target.id == staged.brief.boardID,
              job.providerID == staged.job.providerID,
              job.modelID == staged.job.modelID,
              job.requestSHA256 == staged.job.requestSHA256,
              job.request == staged.job.request else {
            throw Failure.mismatchedJob
        }
        try ProductionBoardApprovals.validate(
            approval, projectID: job.projectID,
            shot: currentShot, board: currentBoard)
        try ProductionImagePlanning.validateCurrent(
            staged.brief, shot: currentShot, board: currentBoard,
            approvedBoardIDs: [approval.boardID])
        // The decode and media store precede candidate construction. A valid
        // candidate is never made from a partial or mismatched provider result.
        let png = try OpenAIReferenceImageResponse.decode(response)
        let storedURL = try BoardImageStorage.store(png, beside: documentURL)
        return try ProductionImageTakeHandoff.candidate(
            brief: staged.brief, currentShot: currentShot,
            currentBoard: currentBoard, approvedBoardIDs: [approval.boardID],
            output: png, storedMediaURL: storedURL, takeID: takeID,
            jobID: job.id, providerID: job.providerID,
            modelID: job.modelID, generatedAt: now)
    }
}
