#if os(macOS)
import CryptoKit
import Darwin
import Foundation
import XCTest
import ShieldApprovalContract
import ShieldApprovalVerification
@testable import ShieldDurableApproval

final class DurableApprovalTests: XCTestCase {
    private let trustedReviewer = "reviewer_01"
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private let c = String(repeating: "c", count: 64)

    private func directory() throws -> URL {
        // Use an isolated 0700 directory under the test user's resolved home.
        // This exercises the intended private application-storage boundary.
        let url = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
            .appendingPathComponent("cips-claim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: Int(0o700))]
        )
        return url
    }
    private func request(
        project: UUID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        request: UUID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        content: String? = nil, destination: String = "provider_one",
        expires: Int64 = 1060
    ) throws -> ApprovalRequestBinding {
        try .init(projectID: project, requestID: request, agentIdentity: "com.example.agent",
                  destinationID: destination, purpose: .analyze, contentSHA256: content ?? a,
                  policySHA256: b, payloadByteCount: 256, issuedAtSeconds: 1000,
                  expiresAtSeconds: expires)
    }
    private func signed(_ request: ApprovalRequestBinding,
                        by key: P256.Signing.PrivateKey) throws -> ReviewerApprovalSignature {
        ReviewerApprovalSignature(
            reviewerKeyID: trustedReviewer,
            signatureDER: try key.signature(
                for: ReviewerApprovalMessage.bytes(for: request)
            ).derRepresentation
        )
    }
    private func verifier(_ key: P256.Signing.PrivateKey) throws -> EphemeralApprovalVerifier {
        try EphemeralApprovalVerifier(trustedReviewerKeys: [
            trustedReviewer: key.publicKey.x963Representation
        ])
    }
    private func database(_ directory: URL) -> URL {
        directory.appendingPathComponent("claims.sqlite")
    }

    func testIndependentCheckpointDetectsRestoredOlderLedger() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let oldCopy = dir.appendingPathComponent("older.sqlite")
        let key = P256.Signing.PrivateKey()
        let first = try request()
        let second = try request(request: UUID(uuidString: "20000000-0000-0000-0000-000000000099")!)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let ledger = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        XCTAssertNil(ledger.claim(try signed(first, by: key), for: first,
                                  atTrustedTime: 1002).failure)
        let firstCheckpoint = try ledger.stateCommitment()
        XCTAssertEqual(firstCheckpoint.claimCount, 1)
        try FileManager.default.copyItem(at: db, to: oldCopy)
        XCTAssertNil(ledger.claim(try signed(second, by: key), for: second,
                                  atTrustedTime: 1003).failure)
        let trustedCheckpoint = try ledger.stateCommitment()
        XCTAssertEqual(trustedCheckpoint.claimCount, 2)
        XCTAssertTrue(ledger.matchesTrustedCheckpoint(trustedCheckpoint))
        XCTAssertFalse(ledger.matchesTrustedCheckpoint(firstCheckpoint))
        try FileManager.default.removeItem(at: db)
        try FileManager.default.copyItem(at: oldCopy, to: db)
        let reopened = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        XCTAssertFalse(reopened.matchesTrustedCheckpoint(trustedCheckpoint))
        XCTAssertTrue(reopened.matchesTrustedCheckpoint(firstCheckpoint))
    }

    func testLedgerDigestStableAcrossReopenAndChangesOnNewClaim() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let key = P256.Signing.PrivateKey()
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let one = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        let empty = try one.stateCommitment()
        XCTAssertEqual(empty.claimCount, 0)
        XCTAssertEqual(empty.sha256Hex.count, 64)
        let two = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        XCTAssertEqual(try two.stateCommitment(), empty)
        let req = try request()
        XCTAssertNil(two.claim(try signed(req, by: key), for: req,
                               atTrustedTime: 1001).failure)
        let changed = try two.stateCommitment()
        XCTAssertEqual(changed.claimCount, 1)
        XCTAssertNotEqual(changed.sha256Hex, empty.sha256Hex)
        XCTAssertFalse(one.matchesTrustedCheckpoint(empty))
        XCTAssertTrue(one.matchesTrustedCheckpoint(changed))
    }

    func testSameClaimCountButDifferentContentHasDifferentCommitment() throws {
        let firstDir = try directory()
        let secondDir = try directory()
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let key = P256.Signing.PrivateKey()
        let firstURL = database(firstDir)
        let secondURL = database(secondDir)
        try DurableApprovalClaimLedger.bootstrap(at: firstURL)
        try DurableApprovalClaimLedger.bootstrap(at: secondURL)
        let first = try DurableApprovalClaimLedger(databaseURL: firstURL, verifier: verifier(key))
        let second = try DurableApprovalClaimLedger(databaseURL: secondURL, verifier: verifier(key))
        let a = try request()
        let b = try request(request: UUID(uuidString: "20000000-0000-0000-0000-000000000077")!)
        XCTAssertNil(first.claim(try signed(a, by: key), for: a, atTrustedTime: 1002).failure)
        XCTAssertNil(second.claim(try signed(b, by: key), for: b, atTrustedTime: 1002).failure)
        let trusted = try first.stateCommitment()
        let different = try second.stateCommitment()
        XCTAssertEqual(trusted.claimCount, different.claimCount)
        XCTAssertNotEqual(trusted.sha256Hex, different.sha256Hex)
        XCTAssertFalse(second.matchesTrustedCheckpoint(trusted))
    }

    func testMissingLedgerNeverMatchesCheckpoint() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let key = P256.Signing.PrivateKey()
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let ledger = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        let expected = try ledger.stateCommitment()
        try FileManager.default.removeItem(at: db)
        XCTAssertFalse(ledger.matchesTrustedCheckpoint(expected))
    }

    func testClaimPersistsAcrossNewVerifierAndLedgerInstance() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let key = P256.Signing.PrivateKey()
        let req = try request()
        let sig = try signed(req, by: key)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        var gate: DurableApprovalClaimLedger? = try .init(databaseURL: db, verifier: verifier(key))
        XCTAssertNil(gate?.claim(sig, for: req, atTrustedTime: 1001).failure)
        gate = nil
        let reopened = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        XCTAssertTrue(try reopened.hasUnknownClaim(projectID: req.projectID, requestID: req.requestID))
        XCTAssertEqual(reopened.claim(sig, for: req, atTrustedTime: 1002).failure, .previouslyClaimed)
    }

    func testForgedOrModifiedSignatureDoesNotClaim() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let attacker = P256.Signing.PrivateKey()
        let req = try request()
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let gate = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        XCTAssertEqual(gate.claim(try signed(req, by: attacker), for: req, atTrustedTime: 1001).failure,
                       .invalidApproval(.invalidSignature))
        XCTAssertEqual(gate.claim(try signed(req, by: key), for: try request(content: c),
                                  atTrustedTime: 1001).failure,
                       .invalidApproval(.invalidSignature))
        XCTAssertFalse(try gate.hasUnknownClaim(projectID: req.projectID, requestID: req.requestID))
        XCTAssertNil(gate.claim(try signed(req, by: key), for: req, atTrustedTime: 1001).failure)
    }

    func testExistingIDCannotBeRepurposedForDifferentDestination() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let gate = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        let a = try request()
        let b = try request(destination: "provider_two")
        XCTAssertNil(gate.claim(try signed(a, by: key), for: a, atTrustedTime: 1001).failure)
        XCTAssertEqual(gate.claim(try signed(b, by: key), for: b, atTrustedTime: 1001).failure,
                       .previouslyClaimed)
    }

    func testConcurrentInstancesOnlyOneSucceeds() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let gates = try (0..<12).map { _ in
            try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        }
        let req = try request()
        let sig = try signed(req, by: key)
        let mutex = NSLock()
        var successes = 0
        var duplicates = 0
        DispatchQueue.concurrentPerform(iterations: gates.count) { i in
            let result = gates[i].claim(sig, for: req, atTrustedTime: 1001)
            mutex.lock()
            if case .success = result { successes += 1 }
            if case .failure(.previouslyClaimed) = result { duplicates += 1 }
            mutex.unlock()
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(duplicates, gates.count - 1)
    }

    func testMissingFileFailsClosedAndNotRecreated() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let key = P256.Signing.PrivateKey()
        XCTAssertThrowsError(try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key)))
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let gate = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        try FileManager.default.removeItem(at: db)
        let req = try request()
        XCTAssertEqual(gate.claim(try signed(req, by: key), for: req, atTrustedTime: 1001).failure,
                       .missingLedger)
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path))
    }

    func testBootstrapCannotReplaceExistingHistory() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        XCTAssertThrowsError(try DurableApprovalClaimLedger.bootstrap(at: db)) { error in
            XCTAssertEqual(error as? DurableClaimError, .alreadyExists)
        }
    }

    func testUnsafeFilePermissionsAndSymlinkRejected() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        let key = P256.Signing.PrivateKey()
        try DurableApprovalClaimLedger.bootstrap(at: db)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o644))],
                                              ofItemAtPath: db.path)
        XCTAssertThrowsError(try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))) {
            XCTAssertEqual($0 as? DurableClaimError, .unsafePath)
        }
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o600))],
                                              ofItemAtPath: db.path)
        let link = dir.appendingPathComponent("linked.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: db)
        XCTAssertThrowsError(try DurableApprovalClaimLedger(databaseURL: link, verifier: verifier(key))) {
            XCTAssertEqual($0 as? DurableClaimError, .unsafePath)
        }
    }

    func testSymlinkedParentDirectoryIsRejected() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let real = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: real)
        let alias = dir.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dir)
        let disguised = alias.appendingPathComponent("claims.sqlite")
        XCTAssertThrowsError(try DurableApprovalClaimLedger(
            databaseURL: disguised, verifier: verifier(key)
        )) { XCTAssertEqual($0 as? DurableClaimError, .unsafePath) }
        XCTAssertThrowsError(try DurableApprovalClaimLedger.bootstrap(at: disguised)) {
            XCTAssertEqual($0 as? DurableClaimError, .unsafePath)
        }
    }

    func testPublicParentDirectoryIsRejected() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int(0o755))], ofItemAtPath: dir.path
        )
        let key = P256.Signing.PrivateKey()
        XCTAssertThrowsError(try DurableApprovalClaimLedger(
            databaseURL: db, verifier: verifier(key)
        )) { XCTAssertEqual($0 as? DurableClaimError, .unsafePath) }
    }

    func testUnreadableOrUninitializedDatabaseFailsClosed() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let db = database(dir)
        try Data("bad sqlite format".utf8).write(to: db)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o600))],
                                              ofItemAtPath: db.path)
        XCTAssertThrowsError(try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key)))
    }

    func testExpiredApprovalDoesNotClaim() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = P256.Signing.PrivateKey()
        let db = database(dir)
        try DurableApprovalClaimLedger.bootstrap(at: db)
        let gate = try DurableApprovalClaimLedger(databaseURL: db, verifier: verifier(key))
        let req = try request()
        let sig = try signed(req, by: key)
        XCTAssertEqual(gate.claim(sig, for: req, atTrustedTime: 1060).failure,
                       .invalidApproval(.expiredOrNotYetValid))
        XCTAssertFalse(try gate.hasUnknownClaim(projectID: req.projectID, requestID: req.requestID))
    }
}
private extension Result where Success == Void, Failure == DurableClaimError {
    var failure: DurableClaimError? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
#endif
