#if os(macOS)
import CryptoKit
import Foundation
import XCTest
import ShieldApprovalContract
import ShieldApprovalVerification
import ShieldDurableApproval
@testable import ShieldCheckpointGate

private enum MockAnchorError: Error { case offline }
/// TEST ONLY: same-process mock has no security isolation or persistence.
private final class MockAnchor: IndependentCheckpointAuthority {
    private let lock = NSLock()
    private var record: AuthoritativeCheckpoint?
    var failLoad = false
    var failAdvance = false
    init(_ value: AuthoritativeCheckpoint?) { record = value }
    func loadLatest() throws -> AuthoritativeCheckpoint {
        lock.lock(); defer { lock.unlock() }
        guard !failLoad, let record else { throw MockAnchorError.offline }
        return record
    }
    func compareAndAdvance(expected: AuthoritativeCheckpoint,
                           replacement: AuthoritativeCheckpoint) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !failAdvance else { throw MockAnchorError.offline }
        guard record == expected, replacement.revision == expected.revision + 1 else { return false }
        record = replacement
        return true
    }
    func replace(_ other: AuthoritativeCheckpoint) {
        lock.lock(); record = other; lock.unlock()
    }
}

final class CheckpointGateTests: XCTestCase {
    private let reviewerID = "reviewer_01"
    private func directory() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
            .appendingPathComponent("cips-anchor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: NSNumber(value: Int(0o700))])
        return url
    }
    private func create() throws -> (URL, DurableApprovalClaimLedger, MockAnchor, P256.Signing.PrivateKey) {
        let root = try directory()
        let db = root.appendingPathComponent("claims.sqlite")
        let key = P256.Signing.PrivateKey()
        let verifier = try EphemeralApprovalVerifier(trustedReviewerKeys: [
            reviewerID: key.publicKey.x963Representation
        ])
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let ledger = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier)
        let anchor = MockAnchor(AuthoritativeCheckpoint(revision: 0, ledger: try ledger.stateCommitment()))
        return (root, ledger, anchor, key)
    }
    private func request(_ id: String = "20000000-0000-0000-0000-000000000002") throws -> ApprovalRequestBinding {
        try ApprovalRequestBinding(
            projectID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            requestID: UUID(uuidString: id)!,
            agentIdentity: "com.example.agent", destinationID: "approved.provider",
            purpose: .analyze, contentSHA256: String(repeating: "a", count: 64),
            policySHA256: String(repeating: "b", count: 64),
            payloadByteCount: 256, issuedAtSeconds: 1000, expiresAtSeconds: 1060)
    }
    private func signed(_ request: ApprovalRequestBinding, by key: P256.Signing.PrivateKey) throws -> ReviewerApprovalSignature {
        ReviewerApprovalSignature(
            reviewerKeyID: reviewerID,
            signatureDER: try key.signature(
                for: ReviewerApprovalMessage.bytes(for: request)
            ).derRepresentation)
    }
    private func failure<T>(_ result: Result<T, CheckpointGateFailure>) -> CheckpointGateFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    func testConsistentAnchorAndAdvanceWithoutDispatch() throws {
        let (dir, ledger, authority, key) = try create()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = CheckpointClaimCoordinator(ledger: ledger, authority: authority)
        XCTAssertNil(failure(gate.checkConsistency()))
        let req = try request()
        let signature = try signed(req, by: key)
        let result = gate.claimAndCheckpoint(signature, for: req, atTrustedTime: 1001)
        XCTAssertNil(failure(result))
        XCTAssertNil(failure(gate.checkConsistency()))
        XCTAssertEqual(try authority.loadLatest().revision, 1)
        XCTAssertTrue(try ledger.hasUnknownClaim(projectID: req.projectID, requestID: req.requestID))
        XCTAssertEqual(failure(gate.claimAndCheckpoint(signature, for: req, atTrustedTime: 1002)),
                       .claimRejected(.previouslyClaimed))
    }

    func testMissingAuthorityQuarantinesBeforeClaim() throws {
        let (dir, ledger, authority, key) = try create()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = CheckpointClaimCoordinator(ledger: ledger, authority: authority)
        authority.failLoad = true
        let req = try request()
        let signature = try signed(req, by: key)
        XCTAssertEqual(failure(gate.claimAndCheckpoint(
            signature, for: req, atTrustedTime: 1001
        )), .authorityUnavailable)
        XCTAssertFalse(try ledger.hasUnknownClaim(projectID: req.projectID,
                                                  requestID: req.requestID))
    }

    func testAnchorFailureAfterDurableClaimRequiresQuarantine() throws {
        let (dir, ledger, authority, key) = try create()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gate = CheckpointClaimCoordinator(ledger: ledger, authority: authority)
        let req = try request()
        authority.failAdvance = true
        XCTAssertEqual(failure(gate.claimAndCheckpoint(
            try signed(req, by: key), for: req, atTrustedTime: 1001
        )), .authorityUnavailable)
        XCTAssertTrue(try ledger.hasUnknownClaim(projectID: req.projectID, requestID: req.requestID))
        XCTAssertEqual(failure(gate.checkConsistency()), .mismatchQuarantine)
    }

    func testOlderRestoredLedgerQuarantinedAgainstLatestAnchor() throws {
        let (dir, ledger, authority, key) = try create()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("claims.sqlite")
        let old = dir.appendingPathComponent("old.sqlite")
        try FileManager.default.copyItem(at: db, to: old)
        let gate = CheckpointClaimCoordinator(ledger: ledger, authority: authority)
        let req = try request()
        XCTAssertNil(failure(gate.claimAndCheckpoint(
            try signed(req, by: key), for: req, atTrustedTime: 1001
        )))
        try FileManager.default.removeItem(at: db)
        try FileManager.default.copyItem(at: old, to: db)
        XCTAssertEqual(failure(gate.checkConsistency()), .mismatchQuarantine)
    }

    func testStaleAnchorQuarantined() throws {
        let (dir, ledger, authority, key) = try create()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try authority.loadLatest()
        let gate = CheckpointClaimCoordinator(ledger: ledger, authority: authority)
        let req = try request()
        XCTAssertNil(failure(gate.claimAndCheckpoint(
            try signed(req, by: key), for: req, atTrustedTime: 1001
        )))
        authority.replace(old)
        XCTAssertEqual(failure(gate.checkConsistency()), .mismatchQuarantine)
    }
}
#endif
