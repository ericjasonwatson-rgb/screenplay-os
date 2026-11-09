# macOS tester app packaging

The packaging branch is stacked on the verified PR #19 commit
`9483eaa93f20b7b62a42c793dfe9339c9b85afe7`. It changes packaging only; the native
editor's video/audio/export gates remain unchanged.

## Reproduce (maintainers)

Use a clean checkout of the desired commit on macOS with Xcode 16.4 selected.
Run `bash Scripts/package-tester-app.sh` from the repository. No dependencies are
fetched by this Swift package. The wrapper fixes release configuration, universal
arm64 + x86_64 architecture, ad-hoc signing, tester bundle ID, version 0.1/build 1,
and refuses a supplied signing identity or notary profile. No keychain import,
production file, release-site update or artifact cleanup runs in this workflow.

Outputs are under `dist/macos-tester/<full commit>/`: the app, a permission-preserving
ZIP, README, build/toolchain information and SHA-256 checksum. The full source
commit is also embedded in Info.plist. This is a reproducible procedure, not a
promise of byte-identical ZIPs across Xcode/SDK/runner updates (timestamps, compiler
output and signatures can vary). The workflow fixes macos-15 and Xcode 16.4 and
records their actual versions; rebuilds require those tools to remain available.

## Automated acceptance

The `macOS Tester App` workflow runs on packaging-branch pushes, relevant PRs and
manual dispatch, with read-only repository permissions. PR builds explicitly check
out the PR head so the archive identifies the exact reviewed commit rather than a
synthetic merge. No secrets are passed to the build.

- Both release slices compile and are combined using lipo.
- Both SwiftPM bundles are copied into Contents/Resources before signing. The
  previous packager omitted these, allowing Bundle.module resolution to depend
  on the original build directory.
- The final archive is extracted into a path containing spaces outside the checkout;
  `.build` is moved aside so absolute build-path fallback cannot hide omissions.
- Verification checks bundle metadata, revision, resources, pricing JSON, executable
  permissions, both architectures, runtime dependencies and ad-hoc signature.
- Five tests verify relocation and rejection of missing domain resources, lost
  executable permission, wrong source commit and wrong bundle type.
- A LaunchServices launch must show a normal on-screen window and remain running
  for five additional seconds. The test terminates only the app instance it opened.
- Focused native assembly/video/clock/cache, FDX and editorial identity tests pass
  in release configuration before artifact upload. The existing
  `defendersFixtureRoundTripsWithoutChangingSource` test is explicitly excluded:
  it requires a private production screenplay absent from the public checkout.
  The five synthetic FDX export tests and seven FDX import tests remain selected.
  No live provider calls or production media are used.

The launch check runs only on the disposable CI account. It is not a request to
open the app against a developer's existing projects. Automated launch on the
runner is not downloaded-app Gatekeeper approval, manual editor acceptance,
Intel/Apple Silicon hardware coverage, or proof of every supported macOS version.
The declared deployment target remains macOS 13; CI runs macOS 15.

## Tester download and distribution boundary

See `macos-tester-README.txt` for Finder-only instructions. The Actions artifact is
named `ScreenplayOS-macOS-universal-tester-<full commit>` and retained for 30 days.
After expiry, rerun that exact commit's workflow to obtain a new verified artifact.
Artifacts contain the inner ZIP, not a loose .app, because the artifact service
alone does not preserve Unix executable permission bits.

This build has an ad-hoc signature, no Developer ID identity and no notarization.
It may need the explicit per-app Privacy & Security approval described by Apple:
https://support.apple.com/en-us/102445 (checked 2026-11-09).
Developer ID distribution is a separate authorized release process requiring
signing, hardened runtime, notarization, stapling and a clean-Mac Gatekeeper test.
No claim of that distribution readiness is made here.

The tester bundle ID separates app registration/preferences, but existing shared
application-support paths are unchanged. Use disposable files and quit other
ScreenplayOS copies. Manual acceptance still includes opening, editing, saving,
reopening and switching all five workspaces with disposable material. No typing
performance change is made or claimed; the benchmark remains unchanged.
