import CryptoKit
import Foundation
import ScreenplayDomain

/// Builds the exact JSON body for OpenAI's documented /v1/images/edits API,
/// without credentials, URLSession, network calls or changes to the job ledger.
/// No text-only fallback: the approved board is always included as image input.
///
/// API contract: https://developers.openai.com/api/reference/resources/images/methods/edit
/// Verified 2026-11-05. This does not assert account entitlement or pricing.
enum OpenAIReferenceImageRequest {
    enum Failure: Error, Equatable {
        case unsupportedModel
        case wrongProvider
        case stalePreview
        case missingAuthorization
        case tooLarge
        case invalidPrompt
    }

    static let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!

    // Conservative documented models. Avoid accepting arbitrary user-supplied
    // strings as proof that an adapter supports image references.
    static let supportedModels: Set<String> = [
        "gpt-image-2.5-sunburst", "gpt-image-2.5-flare", "gpt-image-2",
        "gpt-image-1.5"
    ]

    struct FrozenPayload: Sendable {
        let endpoint: URL
        let body: Data
        let bodySHA256: String
        let requestSHA256: String
        let sourceImageSHA256: String
    }

    /// This is an offline serializer, not a send operation. The caller must
    /// separately record controller consent and revalidate immediately before
    /// supplying these bytes to an authenticated transport.
    static func prepare(
        staged: ApprovedProductionImageReview,
        authorization: ProductionImageSendAuthorization,
        approval: ProductionBoardApproval,
        projectID: UUID,
        shot: Shot,
        board: BoardFrame,
        projectRoot: URL
    ) throws -> FrozenPayload {
        guard staged.job.providerID == "openai" else { throw Failure.wrongProvider }
        guard supportedModels.contains(staged.job.modelID) else { throw Failure.unsupportedModel }
        guard authorization.jobID == staged.job.id,
              authorization.requestSHA256 == staged.job.requestSHA256,
              authorization.approvedImageSHA256 == staged.reference.imageSHA256
        else { throw Failure.missingAuthorization }
        try ProductionImageSendGate.revalidate(
            authorization, staged: staged, approval: approval, projectID: projectID,
            shot: shot, board: board, projectRoot: projectRoot,
            providerAcceptsReferenceImages: true)
        guard staged.reference.providerID == "openai",
              staged.reference.modelID == staged.job.modelID else { throw Failure.stalePreview }
        let prompt = staged.job.request.prompt
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.utf8.count <= 32_000 else { throw Failure.invalidPrompt }
        let bytes = staged.reference.imageBytes
        // A base64 data URI is constrained by the endpoint's 20,971,520-character
        // image_url limit, not simply by the original 20 MB PNG limit.
        let encoded = bytes.base64EncodedString()
        let imageURL = "data:image/png;base64," + encoded
        guard imageURL.utf8.count <= 20_971_520 else { throw Failure.tooLarge }
        let payload: [String: Any] = [
            "model": staged.job.modelID,
            "prompt": prompt,
            "images": [["image_url": imageURL]],
            "n": 1,
            "output_format": "png"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return FrozenPayload(
            endpoint: endpoint, body: data, bodySHA256: sha256(data),
            requestSHA256: staged.job.requestSHA256,
            sourceImageSHA256: staged.reference.imageSHA256)
    }

    private static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
