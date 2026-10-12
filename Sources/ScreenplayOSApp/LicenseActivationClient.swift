import Foundation
import ScreenplayDomain

protocol LicenseActivationTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionLicenseActivationTransport: LicenseActivationTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LicenseActivationError.invalidResponse }
        return (data, http)
    }
}

enum LicenseActivationError: Error, Equatable {
    case invalidEndpoint
    case invalidResponse
    case rejected(Int)
}

struct LicenseActivationClient: Sendable {
    let baseURL: URL
    let transport: any LicenseActivationTransport

    init(baseURL: URL = CommerceConfiguration.licenseServiceBaseURL,
         transport: any LicenseActivationTransport = URLSessionLicenseActivationTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func requestCode(email: String) async throws {
        _ = try await post(path: "activation/request", value: LicenseActivationRequest(email: email)) as EmptyResponse
    }

    func exchange(email: String, code: String) async throws -> SignedLicenseFile {
        try await post(path: "activation/exchange", value: LicenseActivationExchange(email: email, code: code))
    }

    private func post<Input: Encodable, Output: Decodable>(path: String, value: Input) async throws -> Output {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https" else { throw LicenseActivationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(value)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw LicenseActivationError.rejected(response.statusCode) }
        if Output.self == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! Output }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Output.self, from: data)
    }
}

private struct EmptyResponse: Codable { init() {} }
