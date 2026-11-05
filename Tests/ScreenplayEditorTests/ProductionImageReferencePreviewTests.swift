import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain

@Suite("Production image exact reference preview")
struct ProductionImageReferencePreviewTests {
    private func fixture() throws -> (URL, GenerationJobRecord, Shot, BoardFrame) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Board Images"), withIntermediateDirectories: true)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(rep.representation(using: .png, properties: [:]))
        let url = root.appendingPathComponent("Board Images/approved.png")
        try bytes.write(to: url)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let shot = Shot(sceneSpineID: "S001", label: "Beach wide")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID,
                               frameNumber: 1, label: "Approved frame", durationSeconds: 3)
        let image = BoardImageVersion(fileURL: url, sha256: sha, prompt: "board", model: "fixture")
        board.imageVersions = [image]; board.selectedImageID = image.id
        let brief = try ProductionImagePlanning.prepare(shot: shot, board: board,
            approvedBoardIDs: [board.id], directingInstruction: "Golden hour, preserve framing")
        let job = try ProductionImageJobPlanning.awaitingConsent(
            brief: brief, shot: shot, board: board, approvedBoardIDs: [board.id],
            projectID: UUID(), jobID: UUID(), providerID: "mock", modelID: "fixture",
            boardRelativePath: "Board Images/approved.png", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return (root, job, shot, board)
    }

    @Test func previewFreezesExactImageBytesAndDoesNotAuthorizeSending() throws {
        let (root, job, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try ProductionImageReferencePreview.prepare(job: job, projectRoot: root,
            providerAcceptsReferenceImages: true)
        #expect(preview.jobID == job.id)
        #expect(preview.requestSHA256 == job.requestSHA256)
        #expect(preview.prompt == job.request.prompt)
        #expect(preview.width == 2 && preview.height == 1)
        #expect(preview.imageSHA256 == job.request.references[0].sha256)
        #expect(preview.imageBytes == (try Data(contentsOf: root.appendingPathComponent("Board Images/approved.png"))))
        #expect(preview.costDisclosure.contains("unavailable"))
        #expect(job.status == .awaitingConsent && job.consentedAt == nil)
    }

    @Test func unsupportedProviderNeverGetsReferencePreview() throws {
        let (root, job, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ProductionImageReferenceReviewError.self) {
            try ProductionImageReferencePreview.prepare(job: job, projectRoot: root,
                providerAcceptsReferenceImages: false)
        }
    }

    @Test func changingReferenceBytesInvalidatesPreview() throws {
        let (root, job, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1,2,3,4]).write(to: root.appendingPathComponent("Board Images/approved.png"))
        #expect(throws: ProductionImageReferenceReviewError.self) {
            try ProductionImageReferencePreview.prepare(job: job, projectRoot: root,
                providerAcceptsReferenceImages: true)
        }
    }

    @Test func symbolicLinksCannotEscapeProject() throws {
        let (root, job, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let folder = root.appendingPathComponent("Board Images")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        #expect(throws: ProductionImageReferenceReviewError.self) {
            try ProductionImageReferencePreview.prepare(job: job, projectRoot: root,
                providerAcceptsReferenceImages: true)
        }
    }
}
