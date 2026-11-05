import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production image review presentation")
@MainActor
struct ProductionImageReviewSheetTests {
    @Test func canRenderFrozenReviewWithoutExecutingAJob() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
        let review = ProductionImageReferenceReview(
            jobID: UUID(), requestSHA256: String(repeating: "c", count: 64),
            providerID: "test-only", modelID: "mock-image",
            prompt: "Keep original shot composition",
            imageSHA256: String(repeating: "a", count: 64),
            imageSizeBytes: bytes.count, width: 1, height: 1,
            expectedCost: nil, imageBytes: bytes)
        let host = NSHostingView(rootView: ProductionImageReviewSheet(review: review, dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 650)
        host.layoutSubtreeIfNeeded()
        #expect(review.costDisclosure.contains("unavailable"))
        #expect(review.prompt == "Keep original shot composition")
        #expect(host.fittingSize.width > 0)
    }
}
