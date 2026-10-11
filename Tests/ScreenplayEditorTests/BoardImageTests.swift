import Foundation
import Testing
import AppKit
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Board image generation and adoption") struct BoardImageTests {
    @Test func providerFailuresExplainTheCauseWithoutExposingKeys() throws {
        let data = try JSONSerialization.data(withJSONObject: ["error": ["code": "insufficient_quota", "message": "Quota exceeded for sk-private-secret. PRIVATE PROMPT"]])
        let error = BoardImageAPI.failure(status: 429, data: data, key: "sk-private-secret", prompt: "PRIVATE PROMPT").message
        #expect(error.contains("HTTP 429"))
        #expect(error.contains("billing credits"))
        #expect(!error.contains("sk-private-secret"))
        #expect(!error.contains("PRIVATE PROMPT"))
        #expect(BoardImageAPI.failure(status: 403, data: Data(), key: "", prompt: "").message.contains("verification"))
        #expect(BoardImageAPI.failure(status: 404, data: Data(), key: "", prompt: "").message.contains("model name"))
        #expect(BoardImageAPI.failure(status: 500, data: Data(), key: "", prompt: "").message.contains("service problem"))
        let generic = BoardImageAPI.sanitizedMessage(
            "Bearer private-token sk-another-secret PRIVATE PROMPT", key: "private-token", prompt: "PRIVATE PROMPT"
        )
        #expect(!generic.contains("private-token"))
        #expect(!generic.contains("sk-another-secret"))
        #expect(!generic.contains("PRIVATE PROMPT"))
    }
    @Test func creditFailureWithoutCodeIsActionable() throws {
        let data = try JSONSerialization.data(withJSONObject: ["error": ["message": "You have no credits remaining."]])
        let message = BoardImageAPI.failure(status: 429, data: data, key: "", prompt: "").message
        #expect(message.contains("Add API credits"))
        #expect(!message.contains("Wait before retrying"))
    }
    @Test func portableImagesSurviveRelocationAndRejectIncompleteCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let source = root.appendingPathComponent("original.json")
        let image = try BoardImageStorage.store(png, beside: source)
        let screenplay = Screenplay(metadata: .init(title: "Portable"), elements: [])
        var doc = OpenScreenplayDocument(project: Project(metadata: .init(title: "Portable", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        var board = BoardFrame(shotID: UUID(), sceneSpineID: "S001", frameNumber: 1, label: "Test")
        let version = BoardImageVersion(fileURL: image, sha256: BoardImageStorage.digest(png), prompt: "Approved", model: "test")
        board.imageVersions = [version]; board.selectedImageID = version.id; doc.boardFrames = [board]
        var unusual = doc
        let unusualURL = image.deletingLastPathComponent().appendingPathComponent("board #1? 100%.png")
        unusual.boardFrames[0].imageVersions[0].fileURL = unusualURL
        let relative = BoardImageStorage.portableReferences(unusual, at: source)
        let roundTrip = try BoardImageStorage.resolved(relative, at: source)
        #expect(roundTrip.boardFrames[0].imageVersions[0].fileURL == unusualURL)
        let external = root.appendingPathComponent("external.png")
        try png.write(to: external)
        try FileManager.default.removeItem(at: image)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: external)
        #expect(throws: (any Error).self) { try BoardImageStorage.store(png, beside: source) }
        try FileManager.default.removeItem(at: image)
        _ = try BoardImageStorage.store(png, beside: source)
        let copy = root.appendingPathComponent("copy")
        try BoardImageStorage.export(doc, to: copy)
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: copy, to: moved)
        try FileManager.default.removeItem(at: image)
        let file = moved.appendingPathComponent("Project.open-screenplay.json")
        let bytes = try Data(contentsOf: file)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(root.path))
        let decoded = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: bytes)
        let resolved = try BoardImageStorage.resolved(decoded, at: file)
        #expect(try BoardImageStorage.read(resolved.boardFrames[0].imageVersions[0]) == png)
        #expect(resolved.boardFrames[0].id == board.id)
        #expect(resolved.boardFrames[0].selectedImageID == version.id)
        let missingCopy = root.appendingPathComponent("missing")
        #expect(throws: (any Error).self) { try BoardImageStorage.export(doc, to: missingCopy) }
        #expect(!FileManager.default.fileExists(atPath: missingCopy.path))
        var unsafe = decoded
        unsafe.boardFrames[0].imageVersions[0].fileURL = URL(string: "../outside.png")!
        #expect(throws: (any Error).self) { try BoardImageStorage.resolved(unsafe, at: file) }
        #expect(throws: (any Error).self) { try BoardImageStorage.export(resolved, to: moved) }
    }
    @Test func requestSendsOnlyReviewedPrompt() throws {
        let request = try BoardImageAPI.request(key: "test-only", model: "image-test", prompt: "Approved shot")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(json["prompt"] as? String == "Approved shot")
        #expect(json["n"] as? Int == 1)
        #expect(json["output_format"] as? String == "png")
        #expect(throws: (any Error).self) { try BoardImageAPI.request(key: "", model: "image", prompt: "x") }
    }
    @Test func invalidImagesAndRemoteURLsAreRejected() throws {
        for object: [String: Any] in [[:], ["data": [["url": "https://example.com/image.png"]]],
            ["data": [["b64_json": Data("not an image".utf8).base64EncodedString()]]]] {
            #expect(throws: (any Error).self) { try BoardImageAPI.parse(JSONSerialization.data(withJSONObject: object)) }
        }
    }
    @Test func validPNGResponseIsDecoded() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": png.base64EncodedString()]]])
        #expect(try BoardImageAPI.parse(response) == png)
    }
    @MainActor @Test func adoptionPreservesBoardTimingVersionsAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "BoardTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: defaults)
        let heading = ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY")
        let screenplay = Screenplay(metadata: .init(title: "Board test"), elements: [heading])
        let document = OpenScreenplayDocument(project: Project(metadata: .init(title: "Board test", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        let file = directory.appendingPathComponent("project.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: file)
        model.loadOpenScreenplay(at: file); model.selectElement(id: heading.id)
        model.generateShotListForSelectedScene(); model.generateBoardsForSelectedScene()
        let shot = try #require(model.shots.first), board = try #require(model.boardFrames.first)
        model.setBoardFrameDuration(7.5, for: board.id)
        let original = try #require(model.document)
        let snapshot = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        #expect(snapshot.sceneExcerpt.contains("INT. ROOM - DAY"))
        #expect(snapshot.prompt.contains("Scene excerpt"))
        let composition = try snapshot.composition(model: model, instruction: snapshot.directingIntent, evaluatedAt: Date())
        #expect(composition.target.id == board.id)
        #expect(composition.request.prompt.contains("COVERED SCREENPLAY"))
        #expect(composition.request.prompt.contains(shot.label))
        let image = BoardImageVersion(fileURL: directory.appendingPathComponent("board.png"), sha256: "test", prompt: "Reviewed prompt", model: "test-model")
        #expect(model.adoptBoardImage(image, snapshot: snapshot))
        #expect(model.boardFrames.first?.id == board.id)
        #expect(model.boardFrames.first?.durationSeconds == 7.5)
        #expect(model.boardFrames.first?.selectedImage == image)
        #expect(!model.adoptBoardImage(image, snapshot: snapshot))
        let adopted = try #require(model.document)
        let reopened = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: JSONEncoder.openScreenplayEncoder().encode(adopted))
        #expect(reopened.boardFrames.first?.selectedImage == image)
        model.undo()
        var undone = try #require(model.document)
        undone.project.metadata.modifiedAt = original.project.metadata.modifiedAt // Autosave refreshes this timestamp.
        #expect(undone == original)
        model.redo()
        var redone = try #require(model.document)
        redone.project.metadata.modifiedAt = adopted.project.metadata.modifiedAt
        #expect(redone == adopted)
        model.generateBoardsForSelectedScene()
        #expect(model.boardFrames.first?.selectedImage == image)
        #expect(model.boardFrames.first?.durationSeconds == 7.5)
        let second = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        let variant = BoardImageVersion(fileURL: directory.appendingPathComponent("variant.png"), sha256: "test2", prompt: "Variant", model: "test-model")
        #expect(model.adoptBoardImage(variant, snapshot: second))
        #expect(model.boardFrames.first?.imageVersions.count == 2)
        model.selectBoardImage(image.id, for: board.id)
        #expect(model.boardFrames.first?.selectedImage == image)
        model.newDocument()
        #expect(!second.isCurrent(model))
    }

    @MainActor @Test func takeProjectionPersistsAndTracksCanonicalBoardSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "TakeProjectionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory,
                                        preferences: defaults, takeRoot: directory)
        let heading = ScreenplayElement(type: .sceneHeading, text: "INT. REVIEW ROOM - DAY")
        let screenplay = Screenplay(metadata: .init(title: "Take review"), elements: [heading])
        let document = OpenScreenplayDocument(
            project: Project(metadata: .init(title: "Take review", author: ""), screenplayID: screenplay.id),
            screenplay: screenplay
        )
        let file = directory.appendingPathComponent("project.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: file)
        model.loadOpenScreenplay(at: file)
        model.selectElement(id: heading.id)
        model.generateShotListForSelectedScene()
        model.generateBoardsForSelectedScene()
        let shot = try #require(model.shots.first)
        let firstSnapshot = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        let first = BoardImageVersion(fileURL: directory.appendingPathComponent("first.png"),
                                      sha256: String(repeating: "a", count: 64),
                                      prompt: "First", model: "fixture-image")
        #expect(model.adoptBoardImage(first, snapshot: firstSnapshot))
        let secondSnapshot = try #require(BoardGenerationSnapshot(model: model, shot: shot))
        let second = BoardImageVersion(fileURL: directory.appendingPathComponent("second.png"),
                                       sha256: String(repeating: "b", count: 64),
                                       prompt: "Second", model: "fixture-image")
        #expect(model.adoptBoardImage(second, snapshot: secondSnapshot))
        #expect(model.takesForSelectedBoardFrame.map(\.id) == [first.id, second.id])
        #expect(model.takesForSelectedBoardFrame.map(\.status) == [.candidate, .selected])
        #expect(model.activeBoardTake?.id == second.id)
        model.playBoardomatic()
        #expect(model.boardomaticIsPlaying)
        #expect(model.activeBoardTake?.id == second.id)
        model.pauseBoardomatic()
        model.beginBoardTakeComparison()
        #expect(model.comparedBoardTakeIDs == [second.id, first.id])
        #expect(model.comparedBoardTakes.map(\.id) == [second.id, first.id])
        model.toggleBoardTakeComparison(second.id)
        #expect(model.comparedBoardTakeIDs == [first.id])
        model.toggleBoardTakeComparison(second.id)
        #expect(model.comparedBoardTakeIDs == [first.id, second.id])

        model.flushTakeSidecar()
        let url = try TakeWorkflow.storageURL(projectID: screenplay.id, root: directory)
        let initial = try TakeFileStore.read(from: url)
        #expect(initial.takes.map(\.id) == [first.id, second.id])
        #expect(initial.takes.map(\.status) == [.candidate, .selected])

        model.selectBoardImage(first.id, for: try #require(model.selectedBoardFrame?.id))
        #expect(model.takesForSelectedBoardFrame.map(\.status) == [.selected, .candidate])
        #expect(model.activeBoardTake?.id == first.id)
        model.flushTakeSidecar()
        let changed = try TakeFileStore.read(from: url)
        #expect(changed.takes.map(\.status) == [.selected, .candidate])
        #expect(changed.sourceRevision != initial.sourceRevision)
        model.newDocument()
        #expect(model.comparedBoardTakeIDs.isEmpty)
    }
}
