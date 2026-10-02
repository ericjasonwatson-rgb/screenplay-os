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

## Responsiveness and Edit estimates follow-up

The high-priority follow-up preserved synchronous safe saves, print-derived page placement, authored text and the existing file format. Changes:

- Collapsed navigation no longer builds its scene list.
- Font choices use a stable native control, populate when opened, and have a fixed intrinsic width. This avoids repeated installed-font inventory construction and measurement during typing. Page navigation also populates on opening.
- Source text/ranges and unchanged source-to-print mappings are reused. Caches are invalidated by source changes, including Undo/Redo; casing and whitespace policies participate in print-map reuse. Cache contents are bounded to the current source.
- Ordinary unchanged text bypasses per-character casing work. Plain paragraphs no longer build styled-text transformations before discovering that they have no formatting runs.
- Writing projections reuse unchanged source and retain their computed UTF-16 length. Page decoration drawing is restricted to visible pages, and unchanged text-view frame sizes are not reassigned.
- Edit spine has an optional, persistent **Estimates** display preference. Script ranges refresh from current scene text and remain distinct from board/placeholder timings. See [scene duration assumptions and current limits](edit-scene-duration-estimates.md).

Same-machine Release benchmark, 15 synchronous insert/layout/display cycles per run, isolated copies:

| Scenario | Median | Maximum |
|---|---:|---:|
| Before follow-up, 132 pages / 2,004 elements, end | 607.6 ms | 886.5 ms |
| After follow-up, same fixture, end | 259.0 ms | 270.8 ms |
| After, middle | 253.9 ms | 268.3 ms |
| After, beginning | 248.8 ms | 261.4 ms |
| After, middle with navigator open | 279.7 ms | 317.2 ms |
| After, 11 pages / 167 elements, end | 113.0 ms | 124.0 ms |

The comparable end-of-document median improved approximately 57%. These are synchronous harness timings, not measured physical key-to-screen latency. They establish a substantial reduction, **not resolution of feature-length responsiveness**. Full print pagination, attributed-text rebuilding and full native page-layout validation remain on the typing path; incremental pagination/layout is still the leading engineering priority. Do not trade away save protection or source/print agreement to hide this cost.

Validation: Debug and Release each passed 198 Swift tests in 36 suites, 37 Python checks, and 14 self-tests (249 checks per configuration). New coverage exercises cache invalidation through insert/Undo/Redo/typography changes, source-span agreement with a fresh projection, Unicode fast paths, font selection, scene estimate changes, toggle behavior, and measured-versus-planned timing precedence. Existing UI journey tests also cover panel visibility, selection retention, mode switching and save/reopen. No new live visual-inspection claim is made. Existing Swift 6 test-harness migration warnings remain.

Evidence: `work/responsiveness-profile.log`, `responsiveness-full-debug.log`, `responsiveness-full-release.log`, and `responsiveness-final-{end,middle,start,navigator,short}.log`. The profiler subprocess could not obtain a process sample in this environment; no sampling result is claimed. Temporary instrumentation was removed.
