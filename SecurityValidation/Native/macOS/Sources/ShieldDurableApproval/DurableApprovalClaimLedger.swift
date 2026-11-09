#if os(macOS)
import CryptoKit
import Darwin
import Foundation
import SQLite3
import ShieldApprovalContract
import ShieldApprovalVerification

/// This records a claimed approval as delivery outcome UNKNOWN.
/// It does not send, schedule, or permit external network operations.
public enum DurableClaimError: Error, Equatable {
    case missingLedger
    case alreadyExists
    case unsafePath
    case corruptOrUninitialized
    case storageFailure
    case previouslyClaimed
    case invalidApproval(ApprovalVerificationError)
}

/// Unkeyed commitment to the SQLite ledger. Only a separately trusted,
/// independently maintained expected value can make this useful for rollback
/// detection. Never accept the expected value from an AI agent.
public struct LedgerStateCommitment: Equatable, Codable {
    public let claimCount: Int64
    public let sha256Hex: String
}

public final class DurableApprovalClaimLedger {
    private static let schemaVersion: Int32 = 1
    private let fileURL: URL
    private let verifier: EphemeralApprovalVerifier

    /// Explicit bootstrap by a trusted installer. Never call this automatically
    /// after data loss; a missing/rolled-back history must stop authorization.
    public static func bootstrap(at url: URL) throws {
        let path = try validatedPath(url)
        var info = stat()
        guard lstat(path, &info) != 0 else { throw DurableClaimError.alreadyExists }
        let fd = Darwin.open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw DurableClaimError.storageFailure }
        _ = Darwin.close(fd)
        do {
            let db = try openCheckedFile(url)
            defer { sqlite3_close(db) }
            try execute("PRAGMA journal_mode=DELETE;", db)
            try execute("PRAGMA synchronous=FULL;", db)
            try execute("""
                CREATE TABLE approval_claims(
                  project_id TEXT NOT NULL,
                  request_id TEXT NOT NULL,
                  binding_sha256 BLOB NOT NULL CHECK(length(binding_sha256) = 32),
                  reviewer_key_id TEXT NOT NULL,
                  claimed_at_seconds INTEGER NOT NULL,
                  outcome TEXT NOT NULL CHECK(outcome='unknown'),
                  PRIMARY KEY(project_id, request_id)
                ) WITHOUT ROWID;
                """, db)
            try execute("PRAGMA user_version=1;", db)
        } catch {
            // An incomplete initial bootstrap should be visibly absent, never
            // an apparently usable empty ledger on restart.
            _ = Darwin.unlink(path)
            throw error
        }
    }

    /// Opening never creates or repairs a missing ledger.
    /// Caller must obtain path and verifier from trusted service configuration,
    /// never a model request.
    public init(databaseURL: URL, verifier: EphemeralApprovalVerifier) throws {
        self.fileURL = databaseURL
        self.verifier = verifier
        let db = try Self.openValidated(databaseURL)
        sqlite3_close(db)
    }

    /// Validates the detached signature before reserving the request ID in
    /// a durable transaction. The resulting UNKNOWN status forbids automatic
    /// replay after restart. There is intentionally no dispatch method.
    @discardableResult
    public func claim(
        _ approval: ReviewerApprovalSignature,
        for expected: ApprovalRequestBinding,
        atTrustedTime nowSeconds: Int64
    ) -> Result<Void, DurableClaimError> {
        switch verifier.verifySignature(approval, for: expected, atTrustedTime: nowSeconds) {
        case .failure(let error): return .failure(.invalidApproval(error))
        case .success: break
        }
        do {
            let db = try Self.openValidated(fileURL)
            defer { sqlite3_close(db) }
            try Self.execute("BEGIN IMMEDIATE TRANSACTION;", db)
            do {
                var stmt: OpaquePointer?
                let sql = """
                    INSERT INTO approval_claims
                    (project_id, request_id, binding_sha256,
                     reviewer_key_id, claimed_at_seconds, outcome)
                    VALUES (?, ?, ?, ?, ?, 'unknown');
                    """
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                      let stmt else { throw DurableClaimError.storageFailure }
                defer { sqlite3_finalize(stmt) }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let project = expected.projectID.uuidString.lowercased()
                let request = expected.requestID.uuidString.lowercased()
                let hash = Data(SHA256.hash(data: ReviewerApprovalMessage.bytes(for: expected)))
                guard sqlite3_bind_text(stmt, 1, project, -1, transient) == SQLITE_OK,
                      sqlite3_bind_text(stmt, 2, request, -1, transient) == SQLITE_OK,
                      hash.withUnsafeBytes({
                          sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(hash.count), transient)
                      }) == SQLITE_OK,
                      sqlite3_bind_text(stmt, 4, approval.reviewerKeyID, -1, transient) == SQLITE_OK,
                      sqlite3_bind_int64(stmt, 5, nowSeconds) == SQLITE_OK else {
                    throw DurableClaimError.storageFailure
                }
                let result = sqlite3_step(stmt)
                if result == SQLITE_CONSTRAINT {
                    throw DurableClaimError.previouslyClaimed
                }
                guard result == SQLITE_DONE, sqlite3_changes(db) == 1 else {
                    throw DurableClaimError.storageFailure
                }
                try Self.execute("COMMIT;", db)
                return .success(())
            } catch {
                try? Self.execute("ROLLBACK;", db)
                throw error
            }
        } catch let error as DurableClaimError {
            return .failure(error)
        } catch {
            return .failure(.storageFailure)
        }
    }

    /// Only for safe diagnosis. The existence of a claim means outcome is
    /// UNKNOWN and must never be interpreted as external delivery.
    public func hasUnknownClaim(projectID: UUID, requestID: UUID) throws -> Bool {
        let db = try Self.openValidated(fileURL)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
              "SELECT 1 FROM approval_claims WHERE project_id=? AND request_id=? AND outcome='unknown' LIMIT 1;",
              -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DurableClaimError.storageFailure
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, projectID.uuidString.lowercased(), -1, transient) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, requestID.uuidString.lowercased(), -1, transient) == SQLITE_OK else {
            throw DurableClaimError.storageFailure
        }
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw DurableClaimError.storageFailure
    }

    /// Read a serialized database snapshot and hash every claim in stable
    /// order. Does NOT anchor or persist a trusted checkpoint by itself.
    public func stateCommitment() throws -> LedgerStateCommitment {
        let db = try Self.openValidated(fileURL)
        defer { sqlite3_close(db) }
        try Self.execute("BEGIN IMMEDIATE TRANSACTION;", db)
        var statement: OpaquePointer?
        do {
            let sql = """
                SELECT project_id, request_id, binding_sha256,
                       reviewer_key_id, claimed_at_seconds, outcome
                FROM approval_claims ORDER BY project_id, request_id;
                """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { throw DurableClaimError.storageFailure }
            var hasher = SHA256()
            hasher.update(data: Data("CIPS-APPROVAL-LEDGER-STATE-V1\n".utf8))
            var count: Int64 = 0
            while true {
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW, count < Int64.max else {
                    throw DurableClaimError.storageFailure
                }
                count += 1
                for column in Int32(0)..<Int32(6) {
                    let type = sqlite3_column_type(stmt, column)
                    guard type != SQLITE_NULL else { throw DurableClaimError.storageFailure }
                    let length = Int(sqlite3_column_bytes(stmt, column))
                    guard length > 0, length <= 2048,
                          let bytes = sqlite3_column_blob(stmt, column) else {
                        throw DurableClaimError.storageFailure
                    }
                    if column == 2 && (type != SQLITE_BLOB || length != 32) {
                        throw DurableClaimError.storageFailure
                    }
                    hasher.update(data: Data("\(length):".utf8))
                    hasher.update(data: Data(bytes: bytes, count: length))
                }
            }
            guard sqlite3_finalize(stmt) == SQLITE_OK else {
                statement = nil
                throw DurableClaimError.storageFailure
            }
            statement = nil
            try Self.execute("COMMIT;", db)
            return LedgerStateCommitment(
                claimCount: count,
                sha256Hex: hasher.finalize().map { String(format: "%02x", $0) }.joined()
            )
        } catch {
            if let statement { sqlite3_finalize(statement) }
            try? Self.execute("ROLLBACK;", db)
            throw error
        }
    }

    /// A missing or inconsistent independently maintained checkpoint fails
    /// closed. This method cannot verify who supplied the expected checkpoint.
    public func matchesTrustedCheckpoint(_ trusted: LedgerStateCommitment) -> Bool {
        guard let current = try? stateCommitment() else { return false }
        return current == trusted
    }

    private static func validatedPath(_ url: URL) throws -> String {
        guard url.isFileURL, url.path.hasPrefix("/"),
              url.pathExtension == "sqlite",
              !url.lastPathComponent.isEmpty else { throw DurableClaimError.unsafePath }
        let parent = url.deletingLastPathComponent().path
        guard url.standardizedFileURL.path == url.path else {
            fputs("[CI diagnostic] nonstandard path; refused\n", stderr)
            throw DurableClaimError.unsafePath
        }
        guard !containsSymlinkAncestor(parent) else {
            fputs("[CI diagnostic] symlink or non-directory ancestor; refused\n", stderr)
            throw DurableClaimError.unsafePath
        }
        var st = stat()
        guard lstat(parent, &st) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              (st.st_mode & mode_t(0o777)) == mode_t(0o700),
              st.st_uid == geteuid() else { throw DurableClaimError.unsafePath }
        return url.path
    }

    private static func containsSymlinkAncestor(_ absoluteParent: String) -> Bool {
        guard absoluteParent.hasPrefix("/") else { return true }
        let components = (absoluteParent as NSString).pathComponents
        var current = "/"
        for (index, component) in components.enumerated()
            where component != "/" && component != "" {
            current = (current as NSString).appendingPathComponent(component)
            var status = stat()
            let result = lstat(current, &status)
            guard result == 0,
                  (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                fputs("[CI diagnostic] ancestor component index=\(index) lstat=\(result) filetype=\(status.st_mode & mode_t(S_IFMT))\n", stderr)
                return true
            }
        }
        return false
    }

    private static func openCheckedFile(_ url: URL) throws -> OpaquePointer {
        let path = try validatedPath(url)
        var st = stat()
        guard lstat(path, &st) == 0 else { throw DurableClaimError.missingLedger }
        guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (st.st_mode & mode_t(0o777)) == mode_t(0o600),
              st.st_uid == geteuid() else { throw DurableClaimError.unsafePath }
        // Apple's SQLite 3.43.2 on macOS can return SQLITE_CANTOPEN for
        // SQLITE_OPEN_NOFOLLOW on an otherwise valid private regular file.
        // Independently reject symbolic-link ancestors and open the final
        // component with POSIX O_NOFOLLOW. Recheck file identity around SQLite.
        // THIS IS NOT RACE-PROOF AGAINST SAME-UID COMPROMISE.
        let guardFD = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard guardFD >= 0 else { throw DurableClaimError.unsafePath }
        defer { _ = Darwin.close(guardFD) }
        var before = stat()
        guard fstat(guardFD, &before) == 0,
              before.st_dev == st.st_dev, before.st_ino == st.st_ino,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw DurableClaimError.unsafePath
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(path, &handle, flags, nil)
        guard openCode == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw DurableClaimError.storageFailure
        }
        var after = stat()
        guard lstat(path, &after) == 0,
              after.st_dev == before.st_dev, after.st_ino == before.st_ino,
              (after.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (after.st_mode & mode_t(0o777)) == mode_t(0o600) else {
            sqlite3_close(db)
            throw DurableClaimError.unsafePath
        }
        sqlite3_busy_timeout(db, 5_000)
        return db
    }

    private static func openValidated(_ url: URL) throws -> OpaquePointer {
        let db = try openCheckedFile(url)
        do {
            try execute("PRAGMA synchronous=FULL;", db)
            guard try integer("PRAGMA user_version;", db) == schemaVersion,
                  try scalar("PRAGMA quick_check;", db) == "ok",
                  try scalar("PRAGMA journal_mode;", db) == "delete" else {
                throw DurableClaimError.corruptOrUninitialized
            }
            return db
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    private static func execute(_ sql: String, _ db: OpaquePointer) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            // Safe CI diagnostic: SQL is a fixed application-owned statement.
            // Never log content, signatures, provider credentials, or file paths.
            fputs("[test-only] ledger SQLite SQL failed code=\(code) statement=\(sql.prefix(60))\n", stderr)
            throw DurableClaimError.storageFailure
        }
    }

    private static func integer(_ sql: String, _ db: OpaquePointer) throws -> Int32 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { throw DurableClaimError.storageFailure }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw DurableClaimError.storageFailure }
        return sqlite3_column_int(stmt, 0)
    }

    private static func scalar(_ sql: String, _ db: OpaquePointer) throws -> String {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { throw DurableClaimError.storageFailure }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_text(stmt, 0) else {
            throw DurableClaimError.storageFailure
        }
        return String(cString: UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self))
    }
}
#endif
