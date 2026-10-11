import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Dialogue assistant privacy and adoption") struct DialogueAssistantTests {
    @Test func providerRequestsUseDistinctAuthenticationAndNoStoredOpenAIResponse() throws {
        for provider in DialogueProvider.allCases {
            let request = try DialogueAPI.request(provider: provider, key: "synthetic-test-key", model: "test-model", prompt: "Only approved context")
            #expect(request.url?.host == provider.host)
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["model"] as? String == "test-model")
            if provider == .openai {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-key")
                #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
                #expect(body["store"] as? Bool == false)
                #expect(body["input"] as? String == "Only approved context")
            } else {
                #expect(request.value(forHTTPHeaderField: "x-api-key") == "synthetic-test-key")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            }
        }
    }
    func response(_ lines: [String], provider: DialogueProvider, complete: Bool = true) throws -> Data {
        let text = String(data: try JSONEncoder().encode(lines), encoding: .utf8)!
        let body: [String: Any] = provider == .openai
        ? ["status": complete ? "completed" : "incomplete", "output": [["content": [["type": "output_text", "text": text]]]]]
        : ["stop_reason": complete ? "end_turn" : "max_tokens", "content": [["type": "text", "text": text]]]
        return try JSONSerialization.data(withJSONObject: body)
    }
    @Test func validatesBothResponseShapesAndRejectsTruncationAndMalformedLines() throws {
        for provider in DialogueProvider.allCases {
            let lines = ["One.", "Two.", "Three."]
            #expect(try DialogueAPI.parse(response(lines, provider: provider), provider: provider) == lines)
            #expect(throws: (any Error).self) { try DialogueAPI.parse(response(lines, provider: provider, complete: false), provider: provider) }
            #expect(throws: (any Error).self) { try DialogueAPI.parse(response(["Same", "Same", "Other"], provider: provider), provider: provider) }
            #expect(throws: (any Error).self) { try DialogueAPI.parse(response(["One\nTwo", "Three", "Four"], provider: provider), provider: provider) }
        }
    }
    @MainActor @Test func contextIsSceneBoundedAndAdoptionIsUndoableAndRejectsStaleScript() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "DialogueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: defaults)
        let screenplay = Screenplay(metadata: ScreenplayMetadata(title: "Test"), elements: [
            .init(type: .sceneHeading, text: "INT. ROOM - DAY"), .init(type: .character, text: "ALICE"),
            .init(type: .dialogue, text: "Original line."), .init(type: .sceneHeading, text: "EXT. SECRET - DAY"),
            .init(type: .action, text: "PRIVATE OTHER SCENE")])
        let document = ScreenplayOSDocument(project: Project(metadata: ProjectMetadata(title: "Test", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        let file = directory.appendingPathComponent("test.json")
        try JSONEncoder.screenplayOSEncoder().encode(document).write(to: file)
        model.loadScreenplayOSDocument(at: file); model.selectElement(id: model.elements[2].id)
        let snapshot = try #require(DialogueSnapshot.capture(model))
        #expect(snapshot.context.contains("ALICE"))
        #expect(!snapshot.context.contains("PRIVATE OTHER SCENE"))
        let original = model.elements
        #expect(snapshot.accept("Replacement.", model: model, insert: false))
        #expect(model.elements[2].text == "Replacement.")
        #expect(!snapshot.accept("Stale overwrite", model: model, insert: false))
        model.undo(); #expect(model.elements == original)
        #expect(snapshot.accept("Additional line.", model: model, insert: true))
        #expect(model.elements[3].type == .dialogue)
        #expect(model.elements[3].text == "Additional line.")
        #expect(model.elements[2] == original[2])
        #expect(model.selectedElementID == model.elements[3].id)
        let inserted = model.elements
        #expect(!snapshot.accept("Duplicate click.", model: model, insert: true))
        #expect(model.elements == inserted)
        model.undo(); #expect(model.elements == original)
        model.redo(); #expect(model.elements == inserted)
        model.undo(); #expect(model.elements == original)
        model.newDocument(); #expect(!snapshot.isCurrent(model))
    }
}
