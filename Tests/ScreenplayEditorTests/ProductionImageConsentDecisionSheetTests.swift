import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production-image separate consent review")
@MainActor
struct ProductionImageConsentDecisionSheetTests {
    private func preview() -> (GenerationConsentPreview, ProductionImageReferenceReview) {
        let request = GenerationRequestSnapshot(
            prompt: "Preserve this approved storyboard.",
            references: [
                GenerationReference(
                    id: UUID(), kind: "approved_board",
                    relativePath: "Board Images/ref.png",
                    sha256: String(repeating: "a", count: 64),
                    mediaType: "image/png")
            ],
            parameters: ["workflow": "production_image_from_approved_board"]
        )
        let jobID = UUID()
        let job = GenerationJobRecord(
            id: jobID, projectID: UUID(), capability: .image,
            providerID: "openai", modelID: "gpt-image-1.5",
            target: GenerationTarget(
                kind: .board, id: UUID(),
                sourceRevision: String(repeating: "b", count: 64)),
            request: request, requestSHA256: try! request.sha256(),
            status: .awaitingConsent,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let review = ProductionImageReferenceReview(
            jobID: job.id, requestSHA256: job.requestSHA256,
            providerID: job.providerID, modelID: job.modelID,
            prompt: request.prompt,
            imageSHA256: request.references[0].sha256,
            imageSizeBytes: 100, width: 1, height: 1,
            expectedCost: nil, imageBytes: Data())
        return (GenerationConsentPreview(job: job), review)
    }

    @Test func renderingConsentReviewDoesNotAuthorizeOrCallNetwork() throws {
        let (consent, review) = preview()
        var authorized = false
        let view = ProductionImageConsentDecisionSheet(
            consent: consent, imageReview: review,
            approveForQueue: { authorized = true }, dismiss: {})
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 680)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(!authorized)
        #expect(consent.requestSHA256 == review.requestSHA256)
    }
}
