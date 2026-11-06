# Cryptographic approval verification v1 — experimental

## Implemented
The helper-independent `ShieldApprovalVerification` target uses Apple's
CryptoKit P-256 ECDSA with SHA-256. It verifies a DER signature over a
domain-separated, canonical `ApprovalRequestBinding`. Public keys must
be provided through an out-of-band trusted reviewer-key registry at verifier
construction. The key in a request is only a key ID; no caller-provided key is
accepted as a trust anchor.

The test suite covers successful verification, exact-once in-process use,
modified content/policy/destination/purpose/expiry/request, invalid or unknown
signer, malformed signature, invalid trust configuration, future/expired
requests, domain separation, and concurrent duplicate attempts.

## Not production authorization
- The demonstration stores spent requests IN MEMORY. Restart resets the state:
  actual dispatch MUST use a secure durable replay/dispatch ledger.
- A valid signature only attests possession of the trusted key. It does not prove
  a user viewed or understood a prompt, or that UI and signing were bound.
- A real reviewer UI must display the exact transfer bytes/risks and require
  fresh user presence; real Secure Enclave keys must be enrolled on correctly
  signed devices, with documented recovery and revocation.
- The trusted gateway, not the AI model, must compute content/policy digests,
  issue stable request IDs, choose registered destinations and supply trusted time.
- Production approval dispatch requires one atomic, durable acceptance gate,
  provider-specific TLS destination validation, audit consistency and receipt
  reconciliation, plus independent adversarial review.
- This module is deliberately NOT imported by the XPC service or enabled
  in ScreenplayOS/CampaignOS. All XPC approval and outbound APIs still deny.
- Test signing keys are generated ephemerally by unit tests; there are no
  committed private credentials, client assets or provider calls.

Reference: Apple CryptoKit P256.Signing API and SecKey ECDSA X9.62
signature encoding. DO NOT use for genuine studio IP or commercial protection.
