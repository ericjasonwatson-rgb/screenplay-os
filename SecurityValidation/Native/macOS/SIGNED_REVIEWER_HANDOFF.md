# Creative IP Shield — Protected reviewer signing handoff

This is a macOS source-code scaffold only. The reviewer app must be
Developer Team-signed, installed and independently authenticated before use.
The existing synthetic ReviewerDemoApp does not invoke this signer.

## Implemented source

ShieldReviewerKeychain/ReviewerAuthenticatedSigning.swift defines
ReviewerKeyStore.signExplicitReview, which:

1. Checks the current process's OS code signature against the configured
   reviewer bundle and Team ID before any prompt or Keychain operation.
2. Consumes an exact, unexpired UI-confirmed preview, with a mutation epoch
   that invalidates a request changed while an OS prompt was visible.
3. Creates a fresh LAContext, sets zero Touch ID reuse, and requests device
   owner authentication. macOS may offer Touch ID, Apple Watch or password;
   this is not a biometric-only guarantee.
4. Queries only an already enrolled Keychain P-256 private key with a
   reviewer-specific application tag under that authentication context.
5. Checks that the key is Secure Enclave-backed; no software-key fallback.
6. Signs the exact domain-separated canonical approval bytes using
   ecdsaSignatureMessageX962SHA256. Returns a detached DER signature and a
   public-key fingerprint. It does not return the private key or transmit data.
7. Checks the review epoch again after signing. A remote trusted service
   must independently validate the signature and single-use approval claim.

## Validated versus remaining

CI checks compilation and denial for an unsigned/ad-hoc test runner before
it can access Keychain or present an authentication prompt. It cannot verify
real hardware enrollment, live user presence, Keychain entitlements, hardened
and notarized application packaging or an authenticated reviewer inbox.

The native XPC helper always denies all operations and does not import the
signing module. No real AI provider is connected; tests use synthetic data.

Production must demonstrate a properly signed physical macOS reviewer app,
its trusted helper-originated requests, genuinely reviewed complete bytes,
fresh owner authentication, protected hardware-backed signing, enrollment,
revocation, rotation, independently trusted reviewer public-key registration,
durable one-use claims and a protected checkpoint authority. Crash
reconciliation and policy/dispatch/receipt binding also remain unresolved.

Do not use this source to protect actual client or studio intellectual
property until independent security review and signed hardware testing.
