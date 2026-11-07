# Reviewer Secure Enclave key — validation-only milestone

This module exists solely for a *future*, separately signed macOS reviewer app. The
agent-facing XPC listener does not import the module. The service still denies
all approval and outbound operations; this branch is not a deployed security product.

## Architecture
The reviewer app is signed with a configured Apple Team ID and bundle ID.
Before attempting key enrollment, the module uses Security.framework to check
the running app's own code-signature requirement. A matching bundle string alone
does not authorize enrollment. A Secure Enclave P-256 private key is created
with device-only, unlocked and user-presence access control. No software-key
fallback or raw private-key export is available.

This phase does NOT sign any authorization token or unlock an approval workflow.
A trusted UI must display the exact asset, project, provider, purpose, digest,
expiry and policy before invoking a future narrowly scoped signing operation.
The agent must never supply an approval credential, reviewer identity, or
permissions policy.

## macOS CI expectations
Test construction of a device-only Secure Enclave key specification and a
user-presence access control object without creating an actual key.
Test that the unsigned/ad-hoc test runner cannot enroll a key.
The runner need not have Secure Enclave hardware or biometrics configured.

## Unresolved security gates
1. Real Developer ID signed/reviewer app and isolated XPC client identities.
2. Trusted reviewer UI with fresh authentication for every sensitive decision.
3. A correctly designed canonical, one-use approval attestation and server
   signature verification under a protected trust anchor.
4. Key rotation, revocation, recovery, device loss and multi-user controls.
5. Durable dispatch/receipt reconciliation and external independent assessment.

Do not treat Secure Enclave enrollment alone as an agent-authorization
mechanism or guarantee that other same-user processes cannot prompt for access.
Use with synthetic data only.
