# Reviewer macOS signing gate — validation-only builds

Two separately compiled reviewer executables exist in the isolated native
validation SwiftPM package.

The ShieldReviewerDemoApp displays fixed synthetic content and a local OS
authentication demonstration. It does not link the protected signer and
cannot pass the release signing gate.

The ShieldReviewerCandidateApp links the ShieldReviewerKeychain signing
module but has no key enrollment, approval, or network actions. At startup it
loads signed Info.plist metadata and checks that the running app has the exact
Developer ID Application identity matching configured Team and reviewer
bundle IDs. Missing or untrusted identity exits 78 before any window opens.

Both targets retain CIPSValidationOnly and CIPSNoRealApprovalOrEgress markers.

## CI acceptance

On GitHub-hosted Mac Debug/Release, the synthetic and candidate apps are
assembled separately. Tests reject duplicate bundle overwrite, invalid
or overlapping identities, unsigned or ad-hoc signatures and an untrusted
candidate launch. Apple's csreq must parse the strict Developer ID
requirement. All tests use synthetic metadata and zero signing secrets.

## Operator-controlled Developer ID test

From the SecurityValidation/Native/macOS directory on a controlled Mac,
build the reviewed source at a specific commit:

    swift build --configuration release

To package the separately signed-capable but intentionally inert candidate:

    python3 Scripts/package_reviewer_app.py assemble-candidate --binary \
      "$(swift build --show-bin-path --configuration release)/ShieldReviewerCandidateApp" \
      --app "/private/path/CreativeIPShieldReviewer.app" \
      --bundle-id "your.real.reviewer.bundle" \
      --team-id "YOURTEAMID" \
      --agent-bundle-id "your.real.agent.bundle" \
      --helper-bundle-id "your.real.helper.bundle" \
      --agent-mach-service "your.real.agentservice" \
      --reviewer-mach-service "your.real.reviewservice"

Then on your own certificate-equipped Mac:

    python3 Scripts/package_reviewer_app.py sign-release \
      --app "/private/path/CreativeIPShieldReviewer.app" \
      --bundle-id "your.real.reviewer.bundle" \
      --team-id "YOURTEAMID" \
      --identity "Developer ID Application: Your Organization (YOURTEAMID)"

The verifier requires Apple's generic root, Developer ID Certification
Authority intermediate OID 1.2.840.113635.100.6.2.6, Developer ID
Application leaf OID 1.2.840.113635.100.6.1.13, exact Team and bundle
identifiers, hardened runtime and secure timestamp. This follows Apple's
TN3127 code-signing requirements guidance.

Critical CLI detail: when calling codesign -R/--test-requirement, a
literal requirement expression MUST be prefixed with an equals sign.
Without it, codesign can interpret the argument as a filename instead
of evaluating the intended requirement. The release verifier uses
-R "=identifier ... and anchor apple generic ...". The CI script includes
a positive identifier-only control that must PASS against an ad-hoc
signed test bundle, plus wrong-ID and strict Developer ID controls
that must FAIL. A negative-only signature test cannot establish that
the requirement parser actually evaluated the intended expression.

This is a private test ceremony, NOT a distribution process. No certificates,
private keys or Keychain passwords should be shared in chat or GitHub.

## Release blockers

No notarization or stapling, Gatekeeper assessment, signed helper and agent
installation, live authenticated XPC reviewer inbox, physical Secure Enclave
enrollment, protected checkpoint service, key rotation/revocation, atomic
approval-to-dispatch, Windows parity or third-party security review exists.

The candidate has no UI action to sign even a synthetic request. The
production helper still unconditionally denies all outbound operations.
Do not use with real customer, advertising agency or studio IP.
