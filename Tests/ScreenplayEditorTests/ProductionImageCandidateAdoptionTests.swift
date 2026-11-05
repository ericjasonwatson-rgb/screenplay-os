import AppKit
import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production-image candidate adoption into Boards")
struct ProductionImageCandidateAdoptionTests {
    private func png(width: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func sample(shotID: UUID, board: BoardFrame, mediaURL: URL, png: Data,
                        id: UUID = UUID()) -> Take {
        let prompt = "Preserve shot framing and lighting."
        let promptSHA = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        return Take(
            id: id, shotID: shotID, boardFrameID: board.id,
            order: board.imageVersions.count, kind: .generatedImage,
            mediaURL: mediaURL, sha256: BoardImageStorage.digest(png),
            durationSeconds: board.durationSeconds, status: .candidate,
            provenance: .init(source: .generationJob,
                generationJobID: UUID(), providerID: "openai",
                modelID: "gpt-image-1.5", prompt: prompt,
                promptSHA256: promptSHA, generatedAt: Date()))
    }

    @Test func pureProjectionKeepsApprovedSelectionAndTiming() throws {
        let id = UUID()
        var board = BoardFrame(shotID: UUID(), sceneSpineID: "S1",
                               frameNumber: 1, label: "Opening", durationSeconds: 4.5)
        let selected = BoardImageVersion(
            fileURL: URL(fileURLWithPath: "/tmp/approved.png"),
            sha256: String(repeating: "a", count: 64), prompt: "board",
            model: "mock")
        board.imageVersions = [selected]
        board.selectedImageID = selected.id
        let before = board
        let take = sample(shotID: board.shotID, board: board,
                          mediaURL: URL(fileURLWithPath: "/tmp/new.png"),
                          png: try png(width: 2), id: id)
        let result = try ProductionImageCandidateAdoption.appending(take, to: [board])
        #expect(result.count == 1)
        #expect(result[0].id == before.id)
        #expect(result[0].shotID == before.shotID)
        #expect(result[0].durationSeconds == before.durationSeconds)
        #expect(result[0].selectedImageID == selected.id)
        #expect(result[0].imageVersions.count == 2)
        #expect(result[0].imageVersions.last?.id == id)
        #expect(result[0].imageVersions.last?.generationJobID == take.provenance.generationJobID)
        #expect(result[0].imageVersions.last?.providerID == "openai")
        #expect(board == before)
        #expect(throws: ProductionImageCandidateAdoption.Failure.duplicateID) {
            try ProductionImageCandidateAdoption.appending(take, to: result)
        }
    }

    @MainActor @Test func appendingAndSelectingAreIndependentlyUndoable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ProductionCandidate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: root, preferences: defaults, takeRoot: root)
        let heading = ScreenplayElement(type: .sceneHeading, text: "EXT. BEACH - DAY")
        let screenplay = Screenplay(metadata: .init(title: "Candidate Test"), elements: [heading])
        let doc = ScreenplayOSDocument(
            project: Project(metadata: .init(title: "Candidate Test", author: ""), screenplayID: screenplay.id),
            screenplay: screenplay)
        let documentURL = root.appendingPathComponent("film.json")
        try JSONEncoder.screenplayOSEncoder().encode(doc).write(to: documentURL)
        model.loadScreenplayOSDocument(at: documentURL)
        model.selectElement(id: heading.id)
        model.generateShotListForSelectedScene()
        model.generateBoardsForSelectedScene()
        let shot = try #require(model.shots.first)
        let initial = try #require(model.boardFrames.first)
        let first = try png(width: 1)
        let firstURL = try BoardImageStorage.store(first, beside: documentURL)
        let boardVersion = BoardImageVersion(fileURL: firstURL,
            sha256: BoardImageStorage.digest(first), prompt: "rough",
            model: "fixture")
        let snapshot = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        #expect(model.adoptBoardImage(boardVersion, snapshot: snapshot))
        let before = try #require(model.boardFrames.first)
        #expect(before.selectedImageID == boardVersion.id)
        let second = try png(width: 2)
        let secondURL = try BoardImageStorage.store(second, beside: documentURL)
        let take = sample(shotID: shot.id, board: before,
            mediaURL: secondURL, png: second)
        #expect(try model.appendProductionImageCandidate(take))
        let candidateBoard = try #require(model.boardFrames.first)
        #expect(candidateBoard.id == initial.id)
        #expect(candidateBoard.imageVersions.count == 2)
        #expect(candidateBoard.selectedImageID == boardVersion.id)
        #expect(candidateBoard.durationSeconds == before.durationSeconds)
        #expect(model.takesForSelectedBoardFrame.count == 2)
        // Shared model gate for Siri's five read-only navigation targets.
        // Changing views must not adopt the candidate or mutate the edit.
        let beforeModes = try #require(model.document)
        for mode in [WorkflowMode.outline, .writing, .directing, .boards, .edit] {
            model.setWorkflowMode(mode)
            #expect(model.document == beforeModes)
            #expect(model.boardFrames.first?.selectedImageID == boardVersion.id)
            #expect(model.boardFrames.first?.durationSeconds == before.durationSeconds)
            #expect(model.boardFrames.first?.imageVersions.count == 2)
        }
        model.setWorkflowMode(.boards)
        let projected = try #require(model.takesForSelectedBoardFrame.first(where: { $0.id == take.id }))
        #expect(projected.status == .candidate)
        #expect(projected.provenance.generationJobID == take.provenance.generationJobID)
        let encoded = try JSONEncoder.screenplayOSEncoder().encode(try #require(model.document))
        let reopened = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: encoded)
        #expect(reopened.boardFrames.first?.imageVersions.count == 2)
        #expect(reopened.boardFrames.first?.selectedImageID == boardVersion.id)

        model.selectBoardImage(take.id, for: before.id)
        #expect(model.boardFrames.first?.selectedImageID == take.id)
        model.undo()
        #expect(model.boardFrames.first?.selectedImageID == boardVersion.id)
        #expect(model.boardFrames.first?.imageVersions.count == 2)
        model.undo()
        #expect(model.boardFrames.first?.imageVersions.count == 1)
        #expect(model.boardFrames.first?.selectedImageID == boardVersion.id)
        model.redo()
        #expect(model.boardFrames.first?.imageVersions.count == 2)
        #expect(model.boardFrames.first?.selectedImageID == boardVersion.id)
        model.redo()
        #expect(model.boardFrames.first?.selectedImageID == take.id)
        #expect(model.boardFrames.first?.durationSeconds == before.durationSeconds)
    }

    @MainActor @Test func candidateRejectsWrongShotAndModifiedMediaWithoutChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try png(width: 2)
        let file = root.appendingPathComponent("take.png")
        try png.write(to: file)
        let board = BoardFrame(shotID: UUID(), sceneSpineID: "S1",
                               frameNumber: 1, label: "Stable", durationSeconds: 4)
        let take = sample(shotID: UUID(), board: board, mediaURL: file, png: png)
        #expect(throws: ProductionImageCandidateAdoption.Failure.wrongTarget) {
            try ProductionImageCandidateAdoption.appending(take, to: [board])
        }
        let wrongTiming = Take(
            id: UUID(), shotID: board.shotID, boardFrameID: board.id,
            kind: .generatedImage, mediaURL: file, sha256: BoardImageStorage.digest(png),
            durationSeconds: 5, status: .candidate, provenance: take.provenance)
        #expect(throws: ProductionImageCandidateAdoption.Failure.invalidCandidate) {
            try ProductionImageCandidateAdoption.appending(wrongTiming, to: [board])
        }
    }
}
