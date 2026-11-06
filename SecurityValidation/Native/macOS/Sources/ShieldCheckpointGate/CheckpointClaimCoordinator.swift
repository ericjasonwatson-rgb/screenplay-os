#if os(macOS)
import Foundation
import ShieldApprovalContract
import ShieldApprovalVerification
import ShieldDurableApproval

/// The checkpoint MUST come from an independently managed authority, never
/// an AI agent, its XPC request, or the same user-writable ledger directory.
public struct AuthoritativeCheckpoint: Equatable {
    public let revision: UInt64
    public let ledger: LedgerStateCommitment

    public init(revision: UInt64, ledger: LedgerStateCommitment) {
        self.revision = revision
        self.ledger = ledger
    }
}

/// Deliberately no local-file implementation. Actual trust-anchor provisioning
/// requires signed service isolation, authenticated access and monotonic state.
public protocol IndependentCheckpointAuthority {
    func loadLatest() throws -> AuthoritativeCheckpoint
    func compareAndAdvance(
        expected: AuthoritativeCheckpoint,
        replacement: AuthoritativeCheckpoint
    ) throws -> Bool
}

public enum CheckpointGateFailure: Error, Equatable {
    case authorityUnavailable
    case ledgerUnavailable
    case mismatchQuarantine
    case claimRejected(DurableClaimError)
    case advanceRejected
    case revisionExhausted
}

/// Validation-only handoff: NO NETWORK, NO DISPATCH TOKEN and NO permission
/// for other software to use the result as an authorization grant.
public final class CheckpointClaimCoordinator {
    private let ledger: DurableApprovalClaimLedger
    private let authority: IndependentCheckpointAuthority

    public init(ledger: DurableApprovalClaimLedger,
                authority: IndependentCheckpointAuthority) {
        self.ledger = ledger
        self.authority = authority
    }

    public func checkConsistency() -> Result<AuthoritativeCheckpoint, CheckpointGateFailure> {
        let latest: AuthoritativeCheckpoint
        do { latest = try authority.loadLatest() }
        catch { return .failure(.authorityUnavailable) }
        guard ledger.matchesTrustedCheckpoint(latest.ledger) else {
            return .failure(.mismatchQuarantine)
        }
        return .success(latest)
    }

    /// This API ONLY records an approval claim and advances the checkpoint.
    /// A failed CAS or crash after the SQLite commit leaves the state
    /// quarantined for explicit trusted recovery, rather than granting egress.
    /// Cross-process coordination and external authority integrity MUST be
    /// independently assessed before connecting to production.
    public func claimAndCheckpoint(
        _ signature: ReviewerApprovalSignature,
        for request: ApprovalRequestBinding,
        atTrustedTime now: Int64
    ) -> Result<AuthoritativeCheckpoint, CheckpointGateFailure> {
        let prior: AuthoritativeCheckpoint
        switch checkConsistency() {
        case .success(let value): prior = value
        case .failure(let error): return .failure(error)
        }
        guard prior.revision < UInt64.max else { return .failure(.revisionExhausted) }
        switch ledger.claim(signature, for: request, atTrustedTime: now) {
        case .failure(let error): return .failure(.claimRejected(error))
        case .success: break
        }
        let newLedger: LedgerStateCommitment
        do { newLedger = try ledger.stateCommitment() }
        catch { return .failure(.ledgerUnavailable) }
        let replacement = AuthoritativeCheckpoint(
            revision: prior.revision + 1, ledger: newLedger
        )
        do {
            guard try authority.compareAndAdvance(
                expected: prior, replacement: replacement
            ) else { return .failure(.advanceRejected) }
        } catch {
            return .failure(.authorityUnavailable)
        }
        return .success(replacement)
    }
}
#endif
