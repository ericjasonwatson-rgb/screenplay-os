import Foundation
import XCTest
@testable import ShieldApprovalContract

final class ApprovalRequestBindingTests: XCTestCase {
    let a = String(repeating: "a", count: 64)
    let b = String(repeating: "b", count: 64)

    func example(agent: String = "com.example.agent", destination: String = "approved.provider",
                 purpose: ApprovalRequestBinding.Purpose = .analyze,
                 content: String? = nil, policy: String? = nil,
                 now: Int64 = 1000, expiry: Int64 = 1060, bytes: Int64 = 256,
                 request: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!) throws -> ApprovalRequestBinding {
        try .init(projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                  requestID: request, agentIdentity: agent, destinationID: destination,
                  purpose: purpose, contentSHA256: content ?? a, policySHA256: policy ?? b,
                  payloadByteCount: bytes, issuedAtSeconds: now, expiresAtSeconds: expiry)
    }

    func testDeterministicCanonicalDataAndDomainSeparation() throws {
        XCTAssertEqual(try example().canonicalBytes, try example().canonicalBytes)
        XCTAssertTrue(String(decoding: try example().canonicalBytes, as: UTF8.self)
            .hasPrefix("22:CIPS-REVIEW-REQUEST-V1"))
    }
    func testSensitiveFieldChangesAlterCanonicalData() throws {
        let baseline = try example().canonicalBytes
        let altered = [
            try example(agent: "com.example.other").canonicalBytes,
            try example(destination: "another.provider").canonicalBytes,
            try example(purpose: .publish).canonicalBytes,
            try example(content: b).canonicalBytes,
            try example(policy: a).canonicalBytes,
            try example(now: 1001).canonicalBytes,
            try example(expiry: 1061).canonicalBytes,
            try example(bytes: 257).canonicalBytes,
            try example(request: UUID()).canonicalBytes
        ]
        XCTAssertTrue(altered.allSatisfy { $0 != baseline })
    }
    func testUnsafeIdentifiersAndDigestsFailClosed() throws {
        for name in ["", "UPPER", "a/b", "http://x", "space name", "bad\nline",
                     "-minus", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try example(agent: name))
            XCTAssertThrowsError(try example(destination: name))
        }
        for digest in ["", a.uppercased(), String(repeating: "a", count: 63),
                       "g" + String(repeating: "a", count: 63)] {
            XCTAssertThrowsError(try example(content: digest))
            XCTAssertThrowsError(try example(policy: digest))
        }
    }
    func testBadLifetimeAndPayloadFailClosed() throws {
        for pair in [(0,0), (1000,1000), (1000,999), (1000,1301), (-1,10)] {
            XCTAssertThrowsError(try example(now: Int64(pair.0), expiry: Int64(pair.1)))
        }
        for value: Int64 in [-1, ApprovalRequestBinding.maximumPayloadBytes + 1] {
            XCTAssertThrowsError(try example(bytes: value))
        }
    }
    func testExclusiveExpiryBoundary() throws {
        let binding = try example()
        XCTAssertFalse(binding.isWithinLifetime(at: 999))
        XCTAssertTrue(binding.isWithinLifetime(at: 1000))
        XCTAssertTrue(binding.isWithinLifetime(at: 1059))
        XCTAssertFalse(binding.isWithinLifetime(at: 1060))
    }
}
