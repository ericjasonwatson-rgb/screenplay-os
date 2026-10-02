# Script page navigation and review packaging

Updated 2026-10-02.

Script mode opens with a compact Pages pane beside the writing surface. Pages toggles the pane; Focus hides it. Go to page opens a scrollable popover, also accepting a printed page label such as 12 or 12A followed by Return. The title page is separate. Pages without mapped editable source are disabled. These controls currently apply to the legacy Script surface, not the separate native-package editor.

The editor uses an always-visible native vertical scrollbar. The page list highlights the page at the top of the visible writing area and follows it while scrolling. This observation is separate from the editing caret and authored document. Page jumps move to the mapped source and restore editor focus. Exact editable pagination still has the existing continuous-layout fallback; Print Preview remains authoritative for unsupported layouts.

## Packaging diagnosis

The previous local app failed strict code-signature verification with “code has no resources but signature indicates they must be present.” The old executable was linker-signed, but the completed app bundle was not correctly sealed. This is a concrete packaging defect, separate from notarization.

The packager now creates and signs a fresh complete bundle in a temporary staging directory, verifies it, copies file contents without Finder metadata/ACLs, and verifies the installed result. It supports Developer ID signing and a preconfigured notarytool profile, but defaults to ad-hoc local signing. A valid ad-hoc signature is **not** Apple notarization or approval for downloaded distribution.

The owner has no Apple Developer Program membership yet. The review ZIP therefore remains unnotarized and can still be blocked by Gatekeeper. Do not advise reviewers to disable Gatekeeper. Normal distribution remains blocked on membership, a Developer ID Application certificate, notarization credentials, and successful notarization. See Apple's [Developer ID guidance](https://developer.apple.com/developer-id/).

## Verification record

The extracted original review ZIP reproduces the invalid-resource-signature failure. The replacement bundle passes strict signature validation. Automated native viewport tests exercise scrolling at 75%, 100%, and 150% zoom, selection preservation, mapped page jumps, and unchanged document/file bytes. The full updated suite contains 199 Swift tests, 37 Python checks, and 14 self-tests.

Interactive visual review completed after unlocking: page-list selection, typed sidebar navigation, popover Go, editor focus restoration, scrolling/highlight tracking, and scrollbar contrast were inspected in the running app. A focus-race guard ignores stale native selection notifications while a page jump is pending. The sidebar and popover include an explicit Go button. A passing signature-integrity check must not be described as a notarized download.

The app in Documents can acquire Finder metadata again after verification. The review ZIP excludes extended metadata and is verified after extraction. The verified running review copy is installed in the local user Applications folder. macOS blocked replacement of a registered app bundle, so it is named ScreenplayOS Review.app.
