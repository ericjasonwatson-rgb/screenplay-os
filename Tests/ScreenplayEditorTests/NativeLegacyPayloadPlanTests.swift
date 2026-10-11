import Foundation
import Testing
import CryptoKit
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Native legacy destination payloads")
struct NativeLegacyPayloadPlanTests {
    private let stamp = "2026-09-12T12:00:00+00:00"

    private func fixture() throws -> (root: URL, source: URL, heading: UUID, sceneAlias: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projectID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let screenplayID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let headingID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        let actionID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
        let alias = "S001"
        let elements = [
            ScreenplayElement(id: headingID, type: .sceneHeading, text: "INT. ROOM - DAY", spineID: alias),
            ScreenplayElement(id: actionID, type: .action, text: "A lamp hums.")
        ]
        let screenplay = Screenplay(id: screenplayID, metadata: .init(title: "Payload"), elements: elements)
        let shot = Shot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000020")!, sceneSpineID: alias,
                        shotNumber: 7, label: "Master", sourceRefs: [.init(screenplayElementID: actionID)])
        let beat = OutlineBeat(id: UUID(uuidString: "00000000-0000-4000-8000-000000000021")!,
                               template: "custom", order: 3, name: "Opening", purpose: "Orient",
                               linkedSceneSpineIDs: [alias])
        let note = ScriptNote(id: UUID(uuidString: "00000000-0000-4000-8000-000000000022")!,
                              screenplayElementID: actionID, sceneSpineID: alias, body: "Keep the hum")
        let document = ScreenplayOSDocument(
            project: Project(id: projectID, metadata: .init(title: "Payload", author: "Writer"), screenplayID: screenplayID),
            screenplay: screenplay, outline: [beat], scriptNotes: [note], shots: [shot]
        )
        let source = root.appendingPathComponent("Source.json")
        try JSONEncoder.screenplayOSEncoder().encode(document).write(to: source)
        return (root, source, headingID, alias)
    }

    @Test func splitsEveryMappedPayloadAndCommitsExactInventory() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let preflight = try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        let identities = try NativeLegacyIdentityPlan.build(from: preflight, createdAt: stamp)
        let plan = try NativeLegacyPayloadPlan.build(from: preflight, identities: identities)
        #expect(Set(plan.payloads.keys).isSuperset(of: [
            "manifest.json", "screenplay.json", "extensions.json", "notes.json", "shots.json",
            "film/outline.json", "film/edit.json", "film/production.json", "film/proposals.json", "film/activity.json"
        ]))
        #expect(plan.inventory.count == plan.payloads.count)
        for (path, bytes) in plan.payloads {
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            #expect(plan.inventory[path] == .init(sha256: digest, bytes: bytes.count))
        }

        let script = try #require(JSONSerialization.jsonObject(with: plan.payloads["screenplay.json"]!) as? [String: Any])
        let elements = try #require(script["elements"] as? [[String: Any]])
        let expectedScene = try #require(identities.sceneMap[item.heading])
        #expect((elements[0]["scene"] as? [String: Any])?["id"] as? String == expectedScene.uuidString.lowercased())

        let outline = try #require(JSONSerialization.jsonObject(with: plan.payloads["film/outline.json"]!) as? [String: Any])
        let beats = try #require(outline["beats"] as? [[String: Any]])
        #expect(beats[0]["linked_scene_ids"] as? [String] == [expectedScene.uuidString.lowercased()])
        let shots = try #require(JSONSerialization.jsonObject(with: plan.payloads["shots.json"]!) as? [String: Any])
        let addenda = try #require(shots["shot_addenda"] as? [[String: Any]])
        #expect(addenda[0]["scene_id"] as? String == expectedScene.uuidString.lowercased())
        #expect(((addenda[0]["shots"] as? [[String: Any]])?[0]["ordinal"] as? Int) == 1)

        let extensionRoot = try #require(JSONSerialization.jsonObject(with: plan.payloads["extensions.json"]!) as? [String: Any])
        let extensions = try #require(extensionRoot["extensions"] as? [String: Any])
        let archive = try #require(extensions["dev.screenplayos.legacy"] as? [String: Any])
        let archivedSource = try JSONSerialization.data(withJSONObject: archive["source"]!, options: [.sortedKeys])
        let originalObject = try JSONSerialization.jsonObject(with: preflight.sourceBytes)
        let normalizedOriginal = try JSONSerialization.data(withJSONObject: originalObject, options: [.sortedKeys])
        #expect(archivedSource == normalizedOriginal)

        let project = try #require(JSONSerialization.jsonObject(with: plan.projectData) as? [String: Any])
        #expect(project["format"] as? String == "screenplayos-project")
        let manifest = try #require(JSONSerialization.jsonObject(with: plan.payloads["manifest.json"]!) as? [String: Any])
        #expect(manifest["format"] as? String == "screenplayos")
        let head = try #require(project["head"] as? [String: Any])
        #expect((head["files"] as? [String: Any])?.count == plan.inventory.count)
        #expect((head["objects"] as? [[String: Any]])?.count == plan.objects.count)
    }

    @Test func repeatedConstructionIsByteDeterministic() throws {
        let item = try fixture(); defer { try? FileManager.default.removeItem(at: item.root) }
        let preflight = try NativeLegacyConversionPlan.prepare(sourceURL: item.source)
        let identities = try NativeLegacyIdentityPlan.build(from: preflight, createdAt: stamp)
        let first = try NativeLegacyPayloadPlan.build(from: preflight, identities: identities)
        let second = try NativeLegacyPayloadPlan.build(from: preflight, identities: identities)
        #expect(first == second)
    }
}
