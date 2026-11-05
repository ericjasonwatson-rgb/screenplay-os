import CryptoKit
import Foundation
import ImageIO

/// A read-only preview of the local media that an image-capable provider would
/// receive. Building this preview never grants consent or invokes a provider.
public struct ProductionImageReferenceReview: Sendable {
    public let jobID: UUID
    public let requestSHA256: String
    public let providerID: String
    public let modelID: String
    public let prompt: String
    public let imageSHA256: String
    public let imageSizeBytes: Int
    public let width: Int
    public let height: Int
    public let expectedCost: GenerationCost?
    /// Image bytes are frozen for the duration of the review, not persisted as
    /// an additional authoritative copy of the storyboard.
    public let imageBytes: Data

    public var costDisclosure: String {
        guard let expectedCost else { return "Estimated provider cost unavailable. Charges may apply." }
        return "\(expectedCost.amountMicros) micros \(expectedCost.currency) (estimate; provider may charge differently)."
    }
}

public enum ProductionImageReferenceReviewError: Error, Equatable {
    case notAwaitingConsent
    case incorrectCapability
    case unsupportedReferenceInput
    case invalidJob
    case missingReference
    case unsafeLocation
    case invalidImage
    case referenceChanged
}

/// Validates the exact bytes held for preview. The calling UI must show these
/// bytes, prompt, provider/model and cost before any explicit send approval.
/// This never changes the GenerationJobRecord state.
public enum ProductionImageReferencePreview {
    public static func prepare(
        job: GenerationJobRecord,
        projectRoot: URL,
        providerAcceptsReferenceImages: Bool
    ) throws -> ProductionImageReferenceReview {
        guard job.status == .awaitingConsent, job.consentedAt == nil,
              job.submittedAt == nil else { throw ProductionImageReferenceReviewError.notAwaitingConsent }
        guard job.capability == .image, job.target.kind == .board else {
            throw ProductionImageReferenceReviewError.incorrectCapability
        }
        guard providerAcceptsReferenceImages else {
            throw ProductionImageReferenceReviewError.unsupportedReferenceInput
        }
        guard job.request.references.count == 1,
              let reference = job.request.references.first,
              reference.kind == "approved_board", reference.mediaType == "image/png",
              job.request.parameters["workflow"] == "production_image_from_approved_board"
        else { throw ProductionImageReferenceReviewError.missingReference }
        guard job.requestSHA256 == (try job.request.sha256()),
              try GenerationJobLedger(projectID: job.projectID, jobs: [job]).validated().jobs.count == 1
        else { throw ProductionImageReferenceReviewError.invalidJob }

        let root = projectRoot.standardizedFileURL
        guard root.isFileURL, !root.path.isEmpty,
              (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({
                  $0.isDirectory == true && $0.isSymbolicLink != true
              }) == true else { throw ProductionImageReferenceReviewError.unsafeLocation }
        let path = reference.relativePath
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains("://"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw ProductionImageReferenceReviewError.unsafeLocation }
        var candidate = root
        for segment in path.split(separator: "/", omittingEmptySubsequences: false) {
            guard !segment.isEmpty, segment != ".", segment != "..", !segment.contains(":")
            else { throw ProductionImageReferenceReviewError.unsafeLocation }
            candidate.appendPathComponent(String(segment))
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw ProductionImageReferenceReviewError.unsafeLocation
            }
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.standardizedFileURL.path.hasPrefix(rootPrefix),
              let attrs = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              attrs.isRegularFile == true, attrs.isSymbolicLink != true,
              let size = attrs.fileSize, size > 0, size <= 20_000_000,
              let bytes = try? Data(contentsOf: candidate), bytes.count == size
        else { throw ProductionImageReferenceReviewError.unsafeLocation }

        let actualHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard actualHash == reference.sha256 else {
            throw ProductionImageReferenceReviewError.referenceChanged
        }
        guard bytes.starts(with: [137,80,78,71,13,10,26,10]),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw ProductionImageReferenceReviewError.invalidImage }

        return ProductionImageReferenceReview(
            jobID: job.id, requestSHA256: job.requestSHA256,
            providerID: job.providerID, modelID: job.modelID,
            prompt: job.request.prompt, imageSHA256: actualHash,
            imageSizeBytes: size, width: width, height: height,
            expectedCost: job.estimatedCost, imageBytes: bytes)
    }
}
