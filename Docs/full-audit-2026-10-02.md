# Functional audit and debug — 2026-10-02

Scope: current macOS prototype, with emphasis on the studio UI changes, source/display mapping, pagination, local persistence, imports, export, and long-script editing. This is a bounded engineering audit, not a certification of feature parity or absence of all defects.

## Confirmed defects addressed

1. A final blank paragraph's caret could be one line below its print-derived location. The extra line fragment was assigned before a subsequent invalidation, which discarded it. Assign it after the final layout pass. A 66-element multiline native-editor regression reproduced a 12-point discrepancy and now passes.
2. Edit spine scene cards retained mixed-case imported headings, unlike the screenplay preview. Apply uppercase to the display label without changing authored text.
3. The opt-in performance harness could report success even when its input document failed to decode: an empty editor and empty model compared equal. Require successful document loading and nonempty content, report page/element counts, and compare editor text to the source-mapped display projection. Discarded initial invalid-fixture timings.
4. Page placement reconstructed native measurement objects for unchanged print fragments on every edit. Add a bounded cache of current-fragment measurements, comparing exact attributed text and width before reuse; page/source offsets remain recomputed.

## Coverage

Existing automated coverage includes failed saves and outside-file changes, first-save collisions, recoverable snapshots, Unicode selection, typing undo groups, rich formatting, native packages, locked pages, dialogue continuations, explicit breaks, title-page repair, FDX title/content separation, reviewed dual-dialogue conversion, DOCX/PDF/text extraction, and independent edit order/playback. Full debug suite passed before the new regression and again after its fix.

Live observation: updated app opened the user's screenplay and reported saved locally. Script controls, persistent Mode/Workspace/Zoom, Edit viewer/spine and white source preview were present. Switching to Outline exposed its beat sheet, structure selector, and linked script preview. The structure picker is the candidate replacement template; the separately labelled current structure can legitimately differ before Replace Beat Sheet. No creative content was edited through the UI during this audit. Exhaustive window-size, assistive-technology, and all-mode interaction testing is not claimed.

## Remaining limitations / priorities

- Long-script latency remains the leading product risk. Benchmark measures synchronous insert/layout/display requests, not hardware key-to-photon latency. It uses a temporary isolated 132-page, 2,004-element fixture, derived by repeating source material; no edits to the user's screenplay.
- Full re-pagination, attributed-string rebuilding, layout validation, and derived UI work still occur for edits. Paragraph measurement reuse is only one part of the necessary incremental editing work.
- DOCX import extracts text; emphasis/images/comments/layout do not transfer. PDF imports selectable text and requires review of reading order; scanned pages require external OCR. Reviewed FDX dual dialogue is converted sequentially, not laid out side by side.
- First-introduction casing uses known dialogue names and can be ambiguous; it is not semantic character recognition.
- Legacy external-file comparison precedes atomic replacement but does not provide an interprocess lock against a simultaneous external writer.
- Native-package and legacy editors do not yet have complete feature parity. Signing/notarization and Final Draft parity are not established by these tests.

Scene-duration direction: show an explicitly labelled estimate range, distinguish dialogue delivery from action allowance, permit filmmaker overrides, and keep estimated script time separate from board durations and measured edit duration. Scene-length bars currently count screenplay elements, not seconds. No duration estimator was added during this audit.

## Measured result

Valid 132-page / 2,004-element fixture, 15 insertions at the document end, same native-window harness:

| Build / implementation | Median cycle | Maximum cycle |
|---|---:|---:|
| Debug, before measurement cache | 979.4 ms | 1,273.5 ms |
| Release, before measurement cache | 678.7 ms | 946.1 ms |
| Release, after measurement cache | 614.6 ms | 894.9 ms |

The release median improved about 9.4%, but remains unsuitable as the long-script responsiveness target. A single-run comparison is directional evidence, not a statistically controlled benchmark. Final debug suite: 192 Swift tests in 34 suites, 37 Python checks, and 14 self-tests (243 total). New coverage verifies trailing-blank caret position and cached/fresh page geometry through 12 → 18 → 12 point font changes.

Evidence logs are in workspace work/: full-audit-tests.log, audit-trailing-blank.log (reproduced failure), full-audit-fixed-tests.log, full-audit-benchmark.log, audit-render-profile.log, audit-cached-benchmark.log, full-audit-final-tests.log, and full-audit-release-tests.log.

Release validation also passed all 243 checks. Existing test-harness warnings remain in LegacyFormattingTests around RunLoop use in async contexts and main-actor isolation; these are Swift 6 migration work, not failures in the current language mode. No clean-warning-build claim is made.
