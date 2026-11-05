import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("OpenAI production image HTTPS request security")
@MainActor
struct OpenAIProductionImageTransportTests {
    private func frozen(
        endpoint: URL = URL(string: "https://api.openai.com/v1/images/edits")!,
        payload: Data = Data(#"{"model":"fixture","prompt":"preserve framing"}"#.utf8),
        digest: String? = nil
    ) -> ProductionImageDispatchPreflight.Ready {
        ProductionImageDispatchPreflight.Ready(
            jobID: UUID(), endpoint: endpoint, body: payload,
            bodySHA256: digest ?? SHA256.hash(data: payload)
                .map { String(format: "%02x", $0) }.joined(),
            consentedAt: Date(), requestSHA256: String(repeating: "a", count: 64))
    }

    @Test func onlyReviewedPayloadGoesToExactHTTPSOrigin() throws {
        let prepared = frozen()
        let request = try OpenAIProductionImageTransport.request(prepared, credential: "test-only-key")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
        #expect(request.httpBody == prepared.body)
        #expect(String(data: prepared.body, encoding: .utf8)?.contains("test-only-key") == false)
    }

    @Test func rejectsTamperedBodyAndMissingKeyWithoutNetwork() throws {
        let badDigest = frozen(digest: String(repeating: "b", count: 64))
        #expect(throws: OpenAIProductionImageTransport.Failure.modifiedPayload) {
            try OpenAIProductionImageTransport.request(badDigest, credential: "test-only-key")
        }
        #expect(throws: OpenAIProductionImageTransport.Failure.invalidCredential) {
            try OpenAIProductionImageTransport.request(frozen(), credential: "")
        }
        #expect(throws: OpenAIProductionImageTransport.Failure.invalidCredential) {
            try OpenAIProductionImageTransport.request(frozen(), credential: "key\r\nInjected: yes")
        }
    }

    @Test func rejectsRedirectTargetsAndQueryChanges() throws {
        for target in [
            "https://evil.example/v1/images/edits",
            "http://api.openai.com/v1/images/edits",
            "https://api.openai.com/v1/images/edits?destination=elsewhere",
            "https://api.openai.com/v1/images/generations",
            "https://api.openai.com:8443/v1/images/edits"
        ] {
            let ready = frozen(endpoint: URL(string: target)!)
            #expect(throws: OpenAIProductionImageTransport.Failure.invalidEndpoint) {
                try OpenAIProductionImageTransport.request(ready, credential: "test-only-key")
            }
        }
    }
}
