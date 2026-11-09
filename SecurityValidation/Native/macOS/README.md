# Creative IP Shield — macOS compile validation

This is an isolated, non-deployable copy of the v0.8 native XPC scaffold.
It is deliberately placed in a draft PR so GitHub-hosted macOS runners can
compile and test the real macOS-only source paths.

## Scope
- Two XPC listeners (agent/reviewer) with distinct signing requirements.
- A Foundation-based strict signing-identity contract and 13 XCTest cases.
- Endpoint implementations always deny and have no network egress.
- No changes to the ScreenplayOS executable, campaign workspace or project data.

## Run locally on Mac
From SecurityValidation/Native/macOS: run swift build, swift test,
swift build -c release, and swift test -c release.

## What a green CI check does NOT prove
- The helper has been bundled, signed, installed, launched or registered.
- The Apple OS has successfully checked real client signatures.
- A user has authenticated or approved an operation.
- The service can protect arbitrary creative apps or browsers.
- Any provider delivery has occurred.
- That this is production-ready security software.

Before dispatch, separate signed apps must exercise wrong-team, wrong-bundle,
unsigned, agent-to-reviewer, incorrect-helper-signature, restart, and
cancellation cases. Secure key custody and trusted UI remain open.
No real client/studio IP should be used in these tests.
