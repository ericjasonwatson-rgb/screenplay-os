import Foundation
import Testing
import CryptoKit
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Native legacy conversion preflight")
struct NativeLegacyConversionPlanTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixture() throws -> (root: URL, source: URL, document: OpenScreenplayDocument, image: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Source.json")
        let folder = root.appendingPathComponent("Board Images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let image = folder.appendingPathComponent("frame.png")
        try png.write(to: image)
        let screenplay = Screenplay(metadata: .init(title: "Native plan"), elements: [])
        var document = OpenScreenplayDocument(
            project: Project(metadata: .init(title: "Native plan", author: ""), screenplayID: screenplay.id),
            screenplay: screenplay
        )
        var board = BoardFrame(shotID: UUID(), sceneSpineID: "S001", frameNumber: 1, label: "Board")
        let first = BoardImageVersion(
            fileURL: URL(string: "Board%20Images/frame.png")!, sha256: digest(png), prompt: "First", model: "model-a"
        )
        let second = BoardImageVersion(
            fileURL: URL(string: "Board%20Images/frame.png")!, sha256: digest(png), prompt: "Second", model: "model-b"
        )
        board.imageVersions = [first, second]
        board.selectedImageID = second.id
        document.boardFrames = [board]
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: source)
        return (root, source, document, image)
    }

    @Test func preservesExactSourceAndBuildsOrderedDeduplicatedMedia() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let original = try Data(contentsOf: item.source)
        let plan = try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        #expect(plan.sourceBytes == original)
        #expect(try Data(contentsOf: item.source) == original)
        #expect(plan.sourceSHA256 == digest(original))
        let expected = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: original)
        #expect(plan.document == expected)
        #expect(plan.media.count == 1)
        #expect(plan.media[0].boardID == item.document.boardFrames[0].id)
        #expect(plan.media[0].selectedVersionID == item.document.boardFrames[0].imageVersions[1].id)
        #expect(plan.media[0].versions.map(\.id) == item.document.boardFrames[0].imageVersions.map(\.id))
        #expect(plan.media[0].versions.map(\.prompt) == ["First", "Second"])
        #expect(plan.media[0].versions.allSatisfy { $0.width == 1 && $0.height == 1 })
        #expect(plan.attachments.count == 1)
        #expect(plan.attachments.values.first?.bytes == png)
        #expect(plan.attachments.keys.first == "attachments/boards/\(digest(png)).png")
    }

    @Test func rejectsDuplicateKeysAndUnknownFields() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let original = try Data(contentsOf: item.source)
        var duplicate = Data("{\"format\":\"open-screenplay\",".utf8)
        duplicate.append(original.dropFirst())
        try duplicate.write(to: item.source)
        #expect(throws: NativeLegacyConversionPlan.Failure.malformedSource) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }

        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["future_field"] = ["must": "survive"]
        try JSONSerialization.data(withJSONObject: object).write(to: item.source)
        do {
            _ = try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
            Issue.record("Expected an unsupported-field failure")
        } catch let failure as NativeLegacyConversionPlan.Failure {
            guard case let .sourceWouldLoseFields(paths) = failure else {
                Issue.record("Unexpected failure: \(failure)"); return
            }
            #expect(paths == ["future_field"])
        }
    }

    @Test func detectsSourceChangeAcrossPlanningInterval() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let original = try Data(contentsOf: item.source)
        var sourceReads = 0
        #expect(throws: NativeLegacyConversionPlan.Failure.sourceChanged) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source) { url, _ in
                if url == item.source {
                    sourceReads += 1
                    if sourceReads == 2 { return original + Data(" ".utf8) }
                }
                return try Data(contentsOf: url)
            }
        }
        #expect(sourceReads == 2)
    }

    @Test func rejectsMissingSelectionRemoteMediaBadHashAndSymlink() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }

        var document = item.document
        document.boardFrames[0].selectedImageID = UUID()
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: item.source)
        #expect(throws: NativeLegacyConversionPlan.Failure.selectedImageMissing(document.boardFrames[0].id)) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }

        document = item.document
        document.boardFrames[0].imageVersions[0].fileURL = URL(string: "https://example.com/frame.png")!
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: item.source)
        #expect(throws: NativeLegacyConversionPlan.Failure.invalidImageURL(document.boardFrames[0].imageVersions[0].id)) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }

        document = item.document
        document.boardFrames[0].imageVersions[0].sha256 = String(repeating: "0", count: 64)
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: item.source)
        #expect(throws: NativeLegacyConversionPlan.Failure.imageDigestMismatch(document.boardFrames[0].imageVersions[0].id)) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }

        try FileManager.default.removeItem(at: item.image)
        let target = item.root.appendingPathComponent("outside.png")
        try png.write(to: target)
        try FileManager.default.createSymbolicLink(at: item.image, withDestinationURL: target)
        try JSONEncoder.openScreenplayEncoder().encode(item.document).write(to: item.source)
        #expect(throws: NativeLegacyConversionPlan.Failure.imageNotRegular(item.document.boardFrames[0].imageVersions[0].id)) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }

        let sourceTarget = item.root.appendingPathComponent("source-target.json")
        try FileManager.default.moveItem(at: item.source, to: sourceTarget)
        try FileManager.default.createSymbolicLink(at: item.source, withDestinationURL: sourceTarget)
        #expect(throws: NativeLegacyConversionPlan.Failure.sourceNotRegular) {
            try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        }
    }
}
