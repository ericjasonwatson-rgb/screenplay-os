import Foundation
import Testing
import CryptoKit
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Native legacy destination identities")
struct NativeLegacyIdentityPlanTests {
    private let projectID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let screenplayID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private let headingID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
    private let stamp = "2026-09-12T12:00:00+00:00"

    private func downstreamFixture(_ data: Data, source: URL) throws -> NativeLegacyConversionPlan {
        let document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return NativeLegacyConversionPlan(sourceURL: source, sourceBytes: data, sourceSHA256: digest,
                                          document: document, media: [], attachments: [:])
    }

    private func fixture() throws -> (root: URL, source: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let heading = ScreenplayElement(id: headingID, type: .sceneHeading, text: "INT. ROOM - DAY", spineID: "S001")
        let screenplay = Screenplay(id: screenplayID, metadata: .init(title: "Identity"), elements: [heading])
        let shot = Shot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000020")!,
                        sceneSpineID: "S001", shotNumber: 1, label: "Master")
        let beat = OutlineBeat(id: UUID(uuidString: "00000000-0000-4000-8000-000000000021")!,
                               template: "custom", order: 1, name: "Beat", purpose: "",
                               linkedSceneSpineIDs: ["S001"])
        let document = ScreenplayOSDocument(
            project: Project(id: projectID, metadata: .init(title: "Identity", author: ""), screenplayID: screenplayID),
            screenplay: screenplay, outline: [beat], shots: [shot]
        )
        let source = root.appendingPathComponent("Source.json")
        try JSONEncoder.screenplayOSEncoder().encode(document).write(to: source)
        return (root, source)
    }

    @Test func identitiesMatchRFC4122UUID5AndReferencesShareOneScene() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let preflight = try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        let plan = try NativeLegacyIdentityPlan.build(from: preflight, createdAt: stamp)
        let expectedScene = UUID(uuidString: "e4d367aa-2233-5451-8c0e-212f8b91b9af")!
        #expect(plan.sceneMap[headingID] == expectedScene)
        #expect(plan.aliases["S001"] == expectedScene)
        #expect(plan.references.count >= 2)
        #expect(plan.references.allSatisfy { $0.targetSceneID == expectedScene })
        #expect(plan.references.contains { $0.sourcePath == "/shots/0/scene_spine_id" })
        #expect(plan.references.contains { $0.sourcePath == "/outline/0/linked_scene_spine_ids/0" })
        #expect(plan.shotAddendumIDs[expectedScene] != nil)

        let rebuilt = try NativeLegacyIdentityPlan.build(from: preflight, createdAt: stamp)
        #expect(rebuilt == plan)
    }

    @Test func sceneIdentitySurvivesHeadingRenameAndReorder() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let original = try NativeLegacyIdentityPlan.build(
            from: NativeLegacyConversionPlan.prepare(sourceURL: item.source), createdAt: stamp
        )
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: item.source)) as? [String: Any])
        var screenplay = try #require(object["screenplay"] as? [String: Any])
        var elements = try #require(screenplay["elements"] as? [[String: Any]])
        var second = elements[0]
        second["id"] = "00000000-0000-4000-8000-000000000030"
        second["spine_id"] = "S002"
        second["text"] = "EXT. FIELD - NIGHT"
        elements[0]["text"] = "INT. RENAMED ROOM - DAY"
        screenplay["elements"] = [second, elements[0]]
        object["screenplay"] = screenplay
        let changedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let changed = try NativeLegacyIdentityPlan.build(
            from: downstreamFixture(changedData, source: item.source), createdAt: stamp
        )
        #expect(changed.sceneMap[headingID] == original.sceneMap[headingID])
    }

    @Test func duplicateAndUnresolvedAliasesFailClosed() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let original = try Data(contentsOf: item.source)
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var screenplay = try #require(object["screenplay"] as? [String: Any])
        var elements = try #require(screenplay["elements"] as? [[String: Any]])
        var duplicate = elements[0]
        duplicate["id"] = "00000000-0000-4000-8000-000000000031"
        elements.append(duplicate); screenplay["elements"] = elements; object["screenplay"] = screenplay
        let duplicateData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let duplicatePreflight = try downstreamFixture(duplicateData, source: item.source)
        #expect(throws: NativeLegacyIdentityPlan.Failure.duplicateSceneAlias("S001")) {
            try NativeLegacyIdentityPlan.build(from: duplicatePreflight, createdAt: stamp)
        }

        object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var shots = try #require(object["shots"] as? [[String: Any]])
        shots[0]["scene_spine_id"] = "S999"; object["shots"] = shots
        let unresolvedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let unresolvedPreflight = try downstreamFixture(unresolvedData, source: item.source)
        #expect(throws: NativeLegacyIdentityPlan.Failure.unresolvedSceneAlias("S999", "/shots/0/scene_spine_id")) {
            try NativeLegacyIdentityPlan.build(from: unresolvedPreflight, createdAt: stamp)
        }
        #expect(throws: NativeLegacyIdentityPlan.Failure.invalidTimestamp) {
            try NativeLegacyIdentityPlan.build(from: unresolvedPreflight, createdAt: "not-a-time")
        }
    }
}
