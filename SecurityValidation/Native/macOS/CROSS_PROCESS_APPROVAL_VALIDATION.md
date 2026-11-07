# Cross-process approval-claim validation (synthetic only)

The `ShieldDurableApprovalFixture` target exists solely for GitHub-hosted macOS CI.
It generates an ephemeral P-256 private key, signs a fixed artificial request,
and outputs only the public key and detached signature to a temporary 0600 file.
It deliberately treats the fixture public key as trusted: this is **not**
a production key enrollment, authorization, or trust-provisioning workflow.

`Scripts/cross_process_approval.py` launches separate macOS processes to verify:
- first claim succeeds, a second process rejects the identical request;
- eight concurrent processes obtain exactly one success and seven duplicate denials;
- signature tampering is rejected without consuming a new valid request ID;
- deleting the database yields failure without silent re-bootstrap.

Because the fixture's trust source is the test file, **these checks prove only
SQL transaction and process-boundary behavior** under synthetic conditions.
They do not establish identity of a real reviewer or entitlement to any asset.
The deployed helper remains disconnected from this executable and all egress.

Unresolved: externally anchored anti-rollback, same-user process compromise,
trusted stable request IDs, atomic policy+approval+dispatch state, provider
delivery receipts, crash recovery, hardware-held signing keys and independent
penetration testing. Never run with genuine client or studio IP.
