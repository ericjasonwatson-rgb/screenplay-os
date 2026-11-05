import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production image offline end-to-end")
@MainActor
struct ProductionImageOfflineEndToEndTests {
    private func png(_ width: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func persistedJobResultAppearsInBoardsAndSelectionIsUndoable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ProductionImageE2E.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: root, preferences: defaults, takeRoot: root)
        let scene = ScreenplayElement(type: .sceneHeading, text: "EXT. CAT ISLAND - SUNRISE")
        let screenplay = Screenplay(metadata: .init(title: "Defenders of Cat Island"), elements: [scene])
        let source = ScreenplayOSDocument(
            project: Project(metadata: .init(title: "Defenders of Cat Island", author: ""),
                             screenplayID: screenplay.id),
            screenplay: screenplay)
        let documentURL = root.appendingPathComponent("island.json")
        try JSONEncoder.screenplayOSEncoder().encode(source).write(to: documentURL)
        model.loadScreenplayOSDocument(at: documentURL)
        model.selectElement(id: scene.id)
        model.generateShotListForSelectedScene()
        model.generateBoardsForSelectedScene()
        let shot = try #require(model.shots.first)
        let storyboard = try #require(model.boardFrames.first)
        let initialPNG = try png(1)
        let initialURL = try BoardImageStorage.store(initialPNG, beside: documentURL)
        let selected = BoardImageVersion(
            fileURL: initialURL, sha256: BoardImageStorage.digest(initialPNG),
            prompt: "Approved sunrise composition", model: "mock")
        let snapshot = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        #expect(model.adoptBoardImage(selected, snapshot: snapshot))
        let board = try #require(model.boardFrames.first)
        let projectID = try #require(model.document?.screenplay.id)
        let approval = try ProductionBoardApprovals.approve(
            projectID: projectID, shot: shot, board: board)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let staged = try ApprovedProductionImageFlow.prepare(
            approval: approval, projectID: projectID, shot: shot, board: board,
            instruction: "Maintain the exact sunrise composition",
            style: "Painterly animation",
            boardRelativePath: "Board Images/" + initialURL.lastPathComponent,
            projectRoot: root, providerID: "openai", modelID: "gpt-image-1.5",
            providerAcceptsReferenceImages: true, jobID: UUID(), at: started)
        let controller = try GenerationJobController(
            projectID: projectID, storageURL: root.appendingPathComponent("jobs.json"))
        let coordinator = ProductionImageConsentCoordinator(controller: controller)
        let preview = try await coordinator.stage(staged)
        _ = try await coordinator.authorize(
            staged: staged, displayedPreview: preview,
            explicitSendApproval: true, approval: approval,
            shot: shot, board: board, projectRoot: root,
            providerAcceptsReferenceImages: true, at: started.addingTimeInterval(1))
        try await controller.markSubmitted(jobID: staged.job.id, at: started.addingTimeInterval(2))
        try await controller.markSucceeded(jobID: staged.job.id, at: started.addingTimeInterval(3))
        let output = try png(2)
        let fixtureResponse = try JSONSerialization.data(withJSONObject: [
            "data": [["b64_json": output.base64EncodedString()]]
        ])
        let candidate = try await ProductionImageResultPreparation.prepareFromPersistedJob(
            response: fixtureResponse, controller: controller,
            staged: staged, currentShot: shot, currentBoard: board,
            approval: approval, documentURL: documentURL,
            takeID: UUID(), now: started.addingTimeInterval(4))
        #expect(try model.appendProductionImageCandidate(candidate))
        let withCandidate = try #require(model.boardFrames.first)
        #expect(withCandidate.selectedImageID == selected.id)
        #expect(withCandidate.durationSeconds == board.durationSeconds)
        #expect(withCandidate.shotID == shot.id)
        #expect(withCandidate.imageVersions.count == 2)
        #expect(model.takesForSelectedBoardFrame.contains(where: {
            $0.id == candidate.id && $0.status == .candidate
        }))
        model.selectBoardImage(candidate.id, for: board.id)
        #expect(model.boardFrames.first?.selectedImageID == candidate.id)
        model.undo()
        #expect(model.boardFrames.first?.selectedImageID == selected.id)
        #expect(model.boardFrames.first?.imageVersions.count == 2)
        model.undo()
        #expect(model.boardFrames.first?.imageVersions.count == 1)
        model.redo()
        #expect(model.boardFrames.first?.imageVersions.count == 2)
        model.redo()
        #expect(model.boardFrames.first?.selectedImageID == candidate.id)
    }
}
