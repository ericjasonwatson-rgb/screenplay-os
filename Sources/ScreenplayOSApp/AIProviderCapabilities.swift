import Foundation

/// Service metadata describes this adapter, not everything a vendor might offer.
struct AIProviderCapabilities: Equatable, Sendable {
    enum Capability: String, Sendable { case text, image, video, voice }
    let providerID: String
    let capabilities: Set<Capability>
    let imageSizes: [String]
    let acceptsReferenceImages: Bool
    /// nil means unknown, never free. Model/account pricing is resolved in AI-1.
    let pricingHint: String?
}

protocol TextAssist: Sendable {
    var capabilities: AIProviderCapabilities { get }
    func models(key: String) async throws -> [String]
    func suggest(key: String, model: String, prompt: String) async throws -> [String]
}
protocol ImageGeneration: Sendable {
    var capabilities: AIProviderCapabilities { get }
    func generate(key: String, model: String, prompt: String) async throws -> Data
}

/// Reserved service boundaries, not shipped video/voice integrations or job schemas.
/// Media fixtures are supplied by tests/demos; no automatic reading or uploading.
struct AIMediaRequest: Equatable, Sendable {
    let model: String
    let prompt: String
    let durationSeconds: Double
    let referenceAudio: Data?
}
protocol VideoGeneration: Sendable {
    var capabilities: AIProviderCapabilities { get }
    func generateVideo(_ request: AIMediaRequest) async throws -> Data
}
protocol VoiceGeneration: Sendable {
    var capabilities: AIProviderCapabilities { get }
    func generateVoice(_ request: AIMediaRequest) async throws -> Data
}

/// Existing transport retained behind a provider-bound interface.
/// API docs verified 2026-10-10:
/// https://developers.openai.com/api/docs/guides/text
/// https://developers.openai.com/api/reference/resources/models/methods/list
/// https://platform.claude.com/docs/en/api/messages/create
/// https://platform.claude.com/docs/en/api/models/list
struct DialogueTextAdapter: TextAssist {
    let provider: DialogueProvider
    var capabilities: AIProviderCapabilities {
        .init(providerID: provider.rawValue, capabilities: [.text], imageSizes: [],
              acceptsReferenceImages: false, pricingHint: nil)
    }
    func models(key: String) async throws -> [String] {
        try await DialogueAPI().models(provider: provider, key: key)
    }
    func suggest(key: String, model: String, prompt: String) async throws -> [String] {
        try await DialogueAPI().suggest(provider: provider, key: key, model: model, prompt: prompt)
    }
}

/// API docs verified 2026-10-10:
/// https://developers.openai.com/api/reference/go/resources/images/methods/generate
/// This adapter supports the existing one-PNG request only, not every vendor option.
extension BoardImageAPI: ImageGeneration {
    var capabilities: AIProviderCapabilities {
        .init(providerID: "openai", capabilities: [.image], imageSizes: ["1536x1024"],
              acceptsReferenceImages: false, pricingHint: nil)
    }
}

/// Offline deterministic provider. No URLSession, Keychain, files, clock or random IDs.
/// Video/voice fixtures must be supplied explicitly; absent fixtures fail rather
/// than masquerading as generated, decodable production media. Not in the live picker.
struct MockProvider: TextAssist, ImageGeneration, VideoGeneration, VoiceGeneration {
    enum Failure: Error { case requestedFailure, missingFixture }
    let lines: [String]
    let image: Data
    let video: Data?
    let voice: Data?
    let shouldFail: Bool
    init(lines: [String] = ["Stay here.", "Wait for me.", "We go together."],
         image: Data, video: Data? = nil, voice: Data? = nil, shouldFail: Bool = false) {
        self.lines = lines; self.image = image; self.video = video
        self.voice = voice; self.shouldFail = shouldFail
    }
    var capabilities: AIProviderCapabilities {
        .init(providerID: "mock", capabilities: [.text, .image, .video, .voice],
              imageSizes: [], acceptsReferenceImages: false, pricingHint: "Offline fixture; no API charge")
    }
    private func check() throws {
        try Task.checkCancellation()
        if shouldFail { throw Failure.requestedFailure }
    }
    func models(key: String) async throws -> [String] { try check(); return ["mock-fixture-v1"] }
    func suggest(key: String, model: String, prompt: String) async throws -> [String] {
        try check(); return lines
    }
    func generate(key: String, model: String, prompt: String) async throws -> Data {
        try check(); return image
    }
    func generateVideo(_ request: AIMediaRequest) async throws -> Data {
        try check(); guard let video else { throw Failure.missingFixture }; return video
    }
    func generateVoice(_ request: AIMediaRequest) async throws -> Data {
        try check(); guard let voice else { throw Failure.missingFixture }; return voice
    }
}
