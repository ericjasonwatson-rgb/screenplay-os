import Foundation
import XCTest
#if os(macOS)
import Security
#endif
@testable import ShieldNativeContract

final class ContractTests: XCTestCase {
    func config() throws -> SignedPeerConfiguration {
        try SignedPeerConfiguration(
            teamID: "AB12345678",
            agentBundleID: "com.example.shield.agent",
            reviewerBundleID: "com.example.shield.reviewer",
            helperBundleID: "com.example.shield.helper",
            agentMachService: "com.example.shield.agentService",
            reviewerMachService: "com.example.shield.reviewerService")
    }

    func testDistinctSigningRequirements() throws {
        let value = try config()
        XCTAssertNotEqual(value.requirement(for: .agent), value.requirement(for: .reviewer))
        XCTAssertTrue(value.requirement(for: .agent).contains("com.example.shield.agent\""))
        XCTAssertTrue(value.requirement(for: .reviewer).contains("certificate leaf[subject.OU]"))
        XCTAssertTrue(value.helperRequirement().contains("com.example.shield.helper"))
    }
    func testInvalidTeamIDs() {
        for team in ["", "abc1234567", "ABCDE1234", "ABCDE123456", "ABCDEFGH\"1"] {
            XCTAssertThrowsError(try SignedPeerConfiguration(teamID: team, agentBundleID: "com.a.agent", reviewerBundleID: "com.a.reviewer", helperBundleID: "com.a.helper", agentMachService: "com.a.agentservice", reviewerMachService: "com.a.reviewservice"))
        }
    }
    func testBundleStringInjectionDenied() {
        for bundle in ["a", "com.example.\" or true", "com.example.bad name", "com..agent", ".com.agent", "com.agent.", "com.example.☃", "com.example.bad\\escape", "com.example.-agent"] {
            XCTAssertThrowsError(try SignedPeerConfiguration(teamID: "AB12345678", agentBundleID: bundle, reviewerBundleID: "com.a.reviewer", helperBundleID: "com.a.helper", agentMachService: "com.a.agentservice", reviewerMachService: "com.a.reviewservice"), "\(bundle)")
        }
    }
    func testRepeatedBundlesDenied() {
        XCTAssertThrowsError(try SignedPeerConfiguration(teamID: "AB12345678", agentBundleID: "com.a.x", reviewerBundleID: "com.a.x", helperBundleID: "com.a.helper", agentMachService: "com.a.agent", reviewerMachService: "com.a.review"))
    }
    func testSameServiceDenied() {
        XCTAssertThrowsError(try SignedPeerConfiguration(teamID: "AB12345678", agentBundleID: "com.a.agent", reviewerBundleID: "com.a.reviewer", helperBundleID: "com.a.helper", agentMachService: "com.a.sock", reviewerMachService: "com.a.sock"))
    }
    func testNormalAgentRequestDeniedWithoutNativeIntegration() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"prepare"}"#.utf8), role: .agent, requestedOperation: "prepare")
        let decoded = try JSONDecoder().decode(DenialResponse.self, from: result)
        XCTAssertEqual(decoded.status, "denied")
        XCTAssertEqual(decoded.error, .nativeIntegrationPending)
    }
    func testReviewerCannotSubmit() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"submit"}"#.utf8), role: .reviewer, requestedOperation: "submit")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .wrongRole)
    }
    func testAgentCannotApprove() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"approve"}"#.utf8), role: .agent, requestedOperation: "approve")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .wrongRole)
    }
    func testUnknownCommandDenied() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"register"}"#.utf8), role: .reviewer, requestedOperation: "register")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .wrongRole)
    }
    func testMalformedRequestDenied() throws {
        for message in [Data(), Data("hello".utf8), Data("[]".utf8), Data(#"{"op":"prepare","payload":"secret"}"#.utf8)] {
            let result = FailClosedCommandHandler.response(to: message, role: .agent, requestedOperation: "prepare")
            XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .invalidMessage)
        }
    }
    func testOverlargeRequestDenied() throws {
        let result = FailClosedCommandHandler.response(to: Data(repeating: 65, count: FailClosedCommandHandler.maxBytes + 1), role: .agent, requestedOperation: "prepare")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .invalidMessage)
    }
    func testRequestOperationMismatchDenied() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"submit"}"#.utf8), role: .agent, requestedOperation: "prepare")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .invalidMessage)
    }
    func testValidReviewerRequestStillDeniedPendingIntegration() throws {
        let result = FailClosedCommandHandler.response(to: Data(#"{"op":"approve"}"#.utf8), role: .reviewer, requestedOperation: "approve")
        XCTAssertEqual(try JSONDecoder().decode(DenialResponse.self, from: result).error, .nativeIntegrationPending)
    }
    #if os(macOS)
    func testGeneratedRequirementsCompileWithMacSecurityFramework() throws {
        let value = try config()
        for item in [value.requirement(for: .agent), value.requirement(for: .reviewer), value.helperRequirement()] {
            var parsed: SecRequirement?
            let result = SecRequirementCreateWithString(item as CFString, SecCSFlags(rawValue: 0), &parsed)
            XCTAssertEqual(result, errSecSuccess, "macOS rejected code-signing requirement: \(item)")
            XCTAssertNotNil(parsed)
        }
    }
    func testMalformedRequirementCannotBeInstalled() {
        var parsed: SecRequirement?
        let status = SecRequirementCreateWithString("identifier \"unfinished" as CFString, SecCSFlags(rawValue: 0), &parsed)
        XCTAssertNotEqual(status, errSecSuccess)
    }
    #endif

}
