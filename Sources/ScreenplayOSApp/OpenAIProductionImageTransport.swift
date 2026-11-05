import CryptoKit
import Foundation
import ScreenplayDomain

/// Opt-in HTTPS transport for the previously reviewed OpenAI edit-image payload.
/// This adapter is NOT wired into an application Send action. The caller must
/// obtain the user's API key from Keychain after explicit, per-job consent.
@MainActor
struct OpenAIProductionImageTransport: ProductionImageResponseTransport {
    enum Failure: Error, Equatable {
        case invalidCredential
        case invalidEndpoint
        case modifiedPayload
        case requestTooLarge
        case invalidHTTPResponse
        case providerRejected(Int)
        case responseTooLarge
    }

    let credential: String

    init(credential: String) {
        self.credential = credential
    }

    /// Pure preparation: the bearer secret is never serialized into job records,
    /// generation snapshots or a logged error.
    static func request(
        _ prepared: ProductionImageDispatchPreflight.Ready,
        credential: String
    ) throws -> URLRequest {
        guard !credential.isEmpty,
              credential.trimmingCharacters(in: .whitespacesAndNewlines) == credential,
              !credential.contains(where: { $0.isNewline || $0 == "\r" }) else {
            throw Failure.invalidCredential
        }
        guard prepared.endpoint.scheme == "https",
              prepared.endpoint.host == "api.openai.com",
              prepared.endpoint.path == "/v1/images/edits",
              prepared.endpoint.port == nil,
              prepared.endpoint.user == nil,
              prepared.endpoint.password == nil,
              prepared.endpoint.query == nil,
              prepared.endpoint.fragment == nil else {
            throw Failure.invalidEndpoint
        }
        guard !prepared.body.isEmpty, prepared.body.count <= 30_000_000 else {
            throw Failure.requestTooLarge
        }
        let actualDigest = SHA256.hash(data: prepared.body)
            .map { String(format: "%02x", $0) }.joined()
        guard actualDigest == prepared.bodySHA256 else {
            throw Failure.modifiedPayload
        }
        var request = URLRequest(url: prepared.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        request.httpBody = prepared.body
        return request
    }

    func perform(_ prepared: ProductionImageDispatchPreflight.Ready) async throws -> Data {
        // Private session: no cookies/cache, no redirect to another origin.
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        let session = URLSession(
            configuration: config, delegate: DialogueRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let outgoing = try Self.request(prepared, credential: credential)
        let (stream, response) = try await session.bytes(for: outgoing)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.invalidHTTPResponse
        }
        // No provider messages leave this boundary. They can contain prompts,
        // credentials or sensitive creative information.
        guard http.statusCode == 200 else { throw Failure.providerRejected(http.statusCode) }
        var body = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard body.count < OpenAIReferenceImageResponse.maximumResponseBytes else {
                throw Failure.responseTooLarge
            }
            body.append(byte)
        }
        return body
    }
}
