import Foundation
import Testing
import AppKit
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Board image generation and adoption") struct BoardImageTests {
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
}
