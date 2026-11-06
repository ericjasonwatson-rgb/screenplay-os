# Durable approval claim registry — validation-only, no egress

## Purpose
This module bridges signed reviewer approval verification to an independent
SQLite claim that survives helper restarts. It explicitly **does not** send
anything or issue transfer permission. Every successfully claimed request is
marked outcome=unknown: a later transport timeout or crash must never cause
automatic resend under that identity.

## Invariants
1. Only a separately trusted public-key registry is used to validate reviewer
   P-256 signatures over exact content/policy/destination/expiry bytes.
2. `bootstrap(at:)` is an explicit one-time trusted-installer operation. Ordinary
   opening cannot create a missing database or reset an existing history.
3. Parent directory must belong to the running UID, not be a symlink and have
   mode 0700; existing database must be regular, owner-matched and mode 0600.
   SQLite opens with NOFOLLOW and READWRITE, never CREATE, with busy timeout.
4. Each claim uses an independent connection, BEGIN IMMEDIATE + a unique
   project/request primary key and synchronous=FULL before returning success.
   Unknown outcomes cannot be automatically retried. Same ID cannot be
   repurposed for changed content/destination, even if newly signed.
5. Signature failure, expiry, storage errors, missing or corrupted files fail
   closed. Successful claim is not evidence of actual delivery.
6. No network, file contents, client keys, or authorization-to-dispatch functions.

## Still insecure for production
- This is ordinary same-user SQLite storage, not an anti-rollback,
  independently anchored or tamper-proof store. Same-UID malware can edit or
  replace database and policy data. Path checking does not defeat races by
  arbitrary same-UID compromised processes. No safe recovery protocol exists.
- The handoff from a persistent claim to a later provider dispatch remains
  unimplemented; there is no end-to-end atomic transaction across network
  dispatch, receipts, revocation and audit history.
- A malicious caller able to mint a **new** request UUID can bypass per-ID
  replay suppression; a trusted gateway must issue and bind stable request IDs
  and must not expose arbitrary content bytes or destinations for authorization.
- A signature is not proof of informed human approval. Production requires
  a tested, signed reviewer app with Secure Enclave keys, trusted UI and
  fresh user presence, plus OS-protected public-key trust and key rotation.
- No production native helper, Windows equivalent or independent penetration
  assessment. DO NOT USE WITH CUSTOMER/STUDIO DATA.

Tests use synthetic fingerprints and ephemeral test-only signing keys.
