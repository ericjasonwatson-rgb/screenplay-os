import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain

@Suite("Approved storyboard to exact image review")
struct ApprovedProductionImageFlowTests {
    private func fixture() throws -> (URL, UUID, Shot, BoardFrame, ProductionBoardApproval) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("Board Images")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let mediaURL = directory.appendingPathComponent("board.png")
        try data.write(to: mediaURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let projectID = UUID()
        let shot = Shot(sceneSpineID: "S001", label: "Beach wide", notes: "Static camera")
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "S001",
                               frameNumber: 1, label: "Selected storyboard",
                               durationSeconds: 4, notes: "Mew left")
        let version = BoardImageVersion(fileURL: mediaURL, sha256: digest,
            prompt: "Pencil board", model: "fixture")
        board.imageVersions = [version]
        board.selectedImageID = version.id
        let approval = try ProductionBoardApprovals.approve(
            projectID: projectID, shot: shot, board: board)
        return (root, projectID, shot, board, approval)
    }

    @Test func joinsApprovalBriefUnsentJobAndFrozenImage() throws {
        let (root, projectID, shot, board, approval) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Use warm light", style: "2D animation",
            boardRelativePath: "Board Images/board.png", projectRoot: root,
            providerID: "fixture-provider", modelID: "fixture-image",
            providerAcceptsReferenceImages: true, jobID: UUID(), at: Date())
        #expect(staged.approvalID == approval.id)
        #expect(staged.job.status == .awaitingConsent)
        #expect(staged.job.consentedAt == nil && staged.job.submittedAt == nil)
        #expect(staged.reference.jobID == staged.job.id)
        #expect(staged.reference.requestSHA256 == staged.job.requestSHA256)
        #expect(staged.brief.boardID == board.id)
        #expect(staged.reference.imageSHA256 == board.selectedImage?.sha256)
        try ApprovedProductionImageFlow.revalidate(
            staged, approval: approval, projectID: projectID,
            shot: shot, board: board, projectRoot: root,
            providerAcceptsReferenceImages: true)
    }

    @Test func changedBoardAndUnsupportedProviderFailClosed() throws {
        let (root, projectID, shot, board, approval) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let args = (job: UUID(), at: Date())
        #expect(throws: ProductionImageReferenceReviewError.self) {
            try ApprovedProductionImageFlow.prepare(
                approval: approval, projectID: projectID, shot: shot, board: board,
                instruction: "Keep blocking", style: "",
                boardRelativePath: "Board Images/board.png", projectRoot: root,
                providerID: "unsupported", modelID: "fixture",
                providerAcceptsReferenceImages: false, jobID: args.job, at: args.at)
        }
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Keep blocking", style: "",
            boardRelativePath: "Board Images/board.png", projectRoot: root,
            providerID: "fixture", modelID: "fixture",
            providerAcceptsReferenceImages: true, jobID: args.job, at: args.at)
        var altered = board
        altered.notes = "Different staging"
        #expect(throws: ProductionBoardApprovalError.self) {
            try ApprovedProductionImageFlow.revalidate(
                staged, approval: approval, projectID: projectID,
                shot: shot, board: altered, projectRoot: root,
                providerAcceptsReferenceImages: true)
        }
        try Data([0x00, 0x01]).write(to: root.appendingPathComponent("Board Images/board.png"))
        #expect(throws: ProductionImageReferenceReviewError.self) {
            try ApprovedProductionImageFlow.revalidate(
                staged, approval: approval, projectID: projectID,
                shot: shot, board: board, projectRoot: root,
                providerAcceptsReferenceImages: true)
        }
    }
}
