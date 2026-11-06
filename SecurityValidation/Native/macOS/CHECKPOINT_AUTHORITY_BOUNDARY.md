# Independent checkpoint interface — development only

The `ShieldCheckpointGate` library introduces an explicit checkpoint-authority
boundary. A provider is supplied by a trusted native service and must support:
- reading a latest checkpoint (revision + full-ledger commitment);
- compare-and-swap to an incremented revision;
- refusing missing, corrupt, mismatched or unavailable state.

The coordinator first compares the local SQLite digest with the purportedly
independent authority's checkpoint. It then verifies and records the exact
signed request, computes an updated local ledger commitment and requests
an authority CAS. Failure **after** the ledger commit leaves the local record
with `outcome=unknown`, not a permission to send. On subsequent validation the
ledger and prior anchor disagree and the gateway must quarantine the request.

IMPORTANT: This code intentionally provides NO production implementation of
the checkpoint authority. The unit tests use a same-process mock that does
NOT establish isolation, anti-rollback protection, or persistence. No OS
Keychain/Secure Enclave or external storage is automatically trusted here.
The authority must be independently signed, authenticated, versioned and
monotonic, and its enrolled key managed outside the agent or user-writable
ledger storage. This is a contract for a future native service or external
enterprise verifier, NOT an implemented secure anchor.

A crash after SQLite commit and before anchor CAS will quarantine the
ledger; manual reconciliation is unresolved. Cross-process race and malicious
same-UID process file replacement are not prevented. No network dispatch
function or egress is present. Both XPC interfaces still deny. Real IP is
prohibited until OS and independent penetration testing.
