import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("AI provider capability boundaries")
struct AIProviderCapabilityTests {
    private var mock: MockProvider {
        // Transport fixture bytes only; video/voice decoding belongs to later phases.
        MockProvider(image: Data([1, 2]), video: Data([3, 4]), voice: Data([5, 6]))
    }
    @Test func everyCapabilityUsesDeterministicOfflineFixtures() async throws {
        let text: any TextAssist = mock
        let image: any ImageGeneration = mock
        let video: any VideoGeneration = mock
        let voice: any VoiceGeneration = mock
        let request = AIMediaRequest(model: "mock-fixture-v1", prompt: "Fixture", durationSeconds: 2, referenceAudio: nil)
        #expect(try await text.models(key: "") == ["mock-fixture-v1"])
        #expect(try await text.suggest(key: "", model: request.model, prompt: request.prompt) == mock.lines)
        #expect(try await image.generate(key: "", model: request.model, prompt: request.prompt) == Data([1, 2]))
        #expect(try await video.generateVideo(request) == Data([3, 4]))
        #expect(try await voice.generateVoice(request) == Data([5, 6]))
        #expect(try await voice.generateVoice(request) == voice.generateVoice(request))
    }
    @Test func missingMediaFailsInsteadOfInventingAVideo() async throws {
        let provider = MockProvider(image: Data())
        let request = AIMediaRequest(model: "mock", prompt: "", durationSeconds: 1, referenceAudio: nil)
        await #expect(throws: MockProvider.Failure.missingFixture) { try await provider.generateVideo(request) }
        await #expect(throws: MockProvider.Failure.missingFixture) { try await provider.generateVoice(request) }
    }
    @Test func mockFailureAndCancellationAreObservable() async throws {
        let provider = MockProvider(image: Data(), shouldFail: true)
        await #expect(throws: MockProvider.Failure.requestedFailure) {
            try await provider.suggest(key: "", model: "mock", prompt: "")
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await mock.generate(key: "", model: "mock", prompt: "")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func productionCapabilitiesDoNotClaimUnimplementedFeatures() {
        for provider in DialogueProvider.allCases {
            let adapter: any TextAssist = DialogueTextAdapter(provider: provider)
            #expect(adapter.capabilities.providerID == provider.rawValue)
            #expect(adapter.capabilities.capabilities == [.text])
            #expect(adapter.capabilities.pricingHint == nil)
        }
        let image: any ImageGeneration = BoardImageAPI()
        #expect(image.capabilities.capabilities == [.image])
        #expect(image.capabilities.imageSizes == ["1536x1024"])
        #expect(!image.capabilities.acceptsReferenceImages)
        #expect(image.capabilities.pricingHint == nil)
    }
    @Test @MainActor func dialogueConnectionRoutesThroughInjectedProviderWithoutSavingKeys() async throws {
        let name = "AIProviderCapabilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let provider = mock
        let connection = DialogueConnection(defaults: defaults, adapter: { _ in provider })
        connection.key = "offline-fixture" // Never sent: only MockProvider is injected.
        connection.modelID = "mock-fixture-v1"
        connection.run(context: "Selected fixture dialogue")
        for _ in 0..<200 where connection.busy { try await Task.sleep(nanoseconds: 1_000_000) }
        #expect(!connection.busy)
        #expect(connection.alternatives == provider.lines)
        #expect(defaults.string(forKey: "dialogue.provider") == nil)
        connection.changeProvider()
        #expect(connection.alternatives.isEmpty)
        #expect(connection.key.isEmpty)
    }
}
