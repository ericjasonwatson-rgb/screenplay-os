import AppKit
import Foundation
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Final image send confirmation")
@MainActor
struct ProductionImageSendConfirmationSheetTests {
    @Test func mountingConfirmationCannotSendWithoutUserAction() throws {
        let request = GenerationRequestSnapshot(
            prompt: "Maintain the approved framing",
            references: [.init(
                id: UUID(), kind: "approved_board",
                relativePath: "Board Images/approved.png",
                sha256: String(repeating: "a", count: 64),
                mediaType: "image/png")],
            parameters: ["workflow": "production_image_from_approved_board"])
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let job = GenerationJobRecord(
            id: UUID(), projectID: UUID(), capability: .image,
            providerID: "openai", modelID: "gpt-image-1.5",
            target: GenerationTarget(kind: .board, id: UUID(),
                                     sourceRevision: String(repeating: "b", count: 64)),
            request: request, requestSHA256: try request.sha256(),
            status: .awaitingConsent, createdAt: created, updatedAt: created)
        let preview = GenerationConsentPreview(job: job)
        let imageReview = ProductionImageReferenceReview(
            jobID: job.id, requestSHA256: job.requestSHA256,
            providerID: "openai", modelID: job.modelID,
            prompt: request.prompt, imageSHA256: String(repeating: "a", count: 64),
            imageSizeBytes: 10, width: 1, height: 1,
            expectedCost: nil, imageBytes: Data())
        var sent = false
        let host = NSHostingView(rootView: ProductionImageSendConfirmationSheet(
            consent: preview, reference: imageReview,
            confirmSend: { sent = true }, dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 750)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(!sent)
        #expect(preview.requestSHA256 == imageReview.requestSHA256)
    }
}
