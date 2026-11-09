# Reviewer application preview — first macOS UI target

This independent SwiftUI executable compiles an explicit human review window.
It displays the entire *synthetic textual payload*, the effective policy,
destination, purpose, IDs, byte count and digest. It has working Reject and
"Test local authentication" buttons. Local Authentication uses Apple's
device-owner authentication with Touch ID, Apple Watch or device password
depending on the Mac. Authentication success produces **no signature** and
**does not approve anything**. The production helper remains disconnected.

The pure `ShieldReviewerReview` target refuses to display an altered,
non-UTF8, control-character-obfuscated, partial or >16 KiB preview. A
confirmation state is exact-request bound, single-use and expiry checked;
that state machine is not a permission or authentication service.

IMPORTANT: This SwiftPM executable is NOT a signed .app bundle, and the
ReviewerDemoModel loads only fixed synthetic strings. No real client data,
real enrolled Secure Enclave key, review inbox or XPC approval is present.
The UI needs review/accessibility acceptance, separate Developer ID signing,
trusted helper-originated request messages, exact-byte preview validation
and user-presence-backed signing before any production use.

Future: after authenticating reviewer code identity, a real app may obtain
a Secure Enclave signing key from Keychain with a fresh LAContext, sign the
canonical content-bound approval, and return the detached signature to an
independently trusted helper. Verify it and durably claim before dispatch.
Never let an AI agent supply its own trusted key, preview, checkpoint or
requested destination.
