# Synthetic reviewer macOS application packaging

This utility packages ONLY the fixed-data SwiftUI reviewer demonstration
into an ordinary macOS .app. It cannot review an actual request, issue an
approval, enroll a Secure Enclave key, send creative IP, or call the helper.
Info.plist explicitly marks the bundle CIPSValidationOnly and
CIPSNoRealApprovalOrEgress.

GitHub's macOS CI assembles a bundle, validates its Info.plist and file
structure, refuses overwrite, verifies unsigned bundles cannot pass release
validation, refuses an ad-hoc signing identity, then ad-hoc signs a synthetic
copy and checks that the exact Apple Team requirement still fails. CI has
no Developer ID credentials, no Keychain secrets, and no client content.

## Manual signing gate on a controlled Mac

An authorized Apple Developer Team owner can build the release executable
and assemble a test bundle with:

    swift build --configuration release
    python3 Scripts/package_reviewer_app.py assemble --binary       "$(swift build --show-bin-path --configuration release)/ShieldReviewerDemoApp"       --app "/private/path/Reviewer.app"       --bundle-id "your.real.reviewer.bundle"

On a certificate-equipped, controlled Mac the owner can then run:

    python3 Scripts/package_reviewer_app.py sign-release       --app "/private/path/Reviewer.app"       --bundle-id "your.real.reviewer.bundle"       --team-id "YOURTEAMID"       --identity "Developer ID Application: Organization (YOURTEAMID)"

The tool requires hardened runtime and a signing timestamp and verifies an
Apple generic certificate-chain anchor with the exact Team and bundle ID.
It does not notarize or staple a bundle, configure entitlements, establish
a trusted XPC launch service, provision a hardware key or authenticate a
real review request. Do not share signing credentials or certificates in chat.

A signed *synthetic reviewer demo* still is not a production authorization
service. Hardware signing, real secure key enrollment, notarization,
Gatekeeper, trusted helper-originated review delivery, meaningful user
approval and independent audit/recovery remain mandatory. The separate
native helper continues to DENY every real approval and transfer.
