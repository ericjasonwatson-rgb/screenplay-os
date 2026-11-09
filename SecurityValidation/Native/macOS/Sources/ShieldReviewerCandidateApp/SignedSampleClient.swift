#if os(macOS)
import CryptoKit
import Foundation
import ShieldApprovalVerification
import ShieldMacXPCInterfaces
import ShieldNativeContract
import ShieldSignedSample

enum SignedSampleClient {
    private enum SampleError: Error {
        case missingProxy
        case timedOut
        case invalidChallenge
        case unexpectedReply
    }

    private final class Reply {
        private let lock = NSLock()
        private let ready = DispatchSemaphore(value: 0)
        private var result: Result<Data, Error>?

        func finish(_ value: Result<Data, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard result == nil else { return }
            result = value
            ready.signal()
        }

        func wait() throws -> Data {
            guard ready.wait(timeout: .now() + 8) == .success else { throw SampleError.timedOut }
            lock.lock()
            defer { lock.unlock() }
            guard let result else { throw SampleError.timedOut }
            return try result.get()
        }
    }

    static func run(configuration: SignedPeerConfiguration) -> Int32 {
        let connection = NSXPCConnection(machServiceName: configuration.reviewerMachService, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: ShieldSignedSampleXPC.self)
        connection.setCodeSigningRequirement(configuration.helperRequirement())
        connection.resume()
        defer { connection.invalidate() }

        func request(_ call: (ShieldSignedSampleXPC, @escaping (NSData) -> Void) -> Void) throws -> Data {
            let reply = Reply()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({
                reply.finish(.failure($0))
            }) as? ShieldSignedSampleXPC else { throw SampleError.missingProxy }
            call(proxy) { reply.finish(.success($0 as Data)) }
            return try reply.wait()
        }

        do {
            let response = try request { $0.challenge($1) }
            guard response.count <= 512,
                  let challenge = try? JSONDecoder().decode(SignedSample.Challenge.self, from: response),
                  let binding = try? challenge.binding(),
                  binding.isWithinLifetime(at: SignedSample.now)
            else { throw SampleError.invalidChallenge }

            print("Sample content: \(SignedSample.content)")
            print("Destination: \(SignedSample.destination)")
            print("Purpose: \(binding.purpose.rawValue)")
            print("Policy: \(SignedSample.policy)")
            print("Type APPROVE SAMPLE to verify this local test, or press Return to stop.")
            fflush(stdout)
            guard readLine() == "APPROVE SAMPLE" else {
                print("Sample canceled.")
                return 2
            }

            let key = try SignedSample.fixtureKey()
            let message = ReviewerApprovalMessage.bytes(for: binding)
            let alteredSignature = try key.signature(for: message + Data([0])).derRepresentation
            let signature = try key.signature(for: message).derRepresentation
            func verify(_ bytes: Data, expecting status: String) throws {
                let response = try request { $0.verifySample(bytes as NSData, withReply: $1) }
                guard response == Data(status.utf8) else { throw SampleError.unexpectedReply }
            }

            try verify(alteredSignature, expecting: "denied")
            try verify(signature, expecting: "verified")
            try verify(signature, expecting: "replay-denied")
            print("PASS: signed helper rejected a signature over altered bytes, verified the sample approval, and rejected replay.")
            return 0
        } catch {
            fputs("Signed sample failed: \(error)\n", stderr)
            return 1
        }
    }
}
#endif
