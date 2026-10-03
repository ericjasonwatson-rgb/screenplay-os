# Long-script typing measurement

Measured on this Mac using a release build, a synthetic 1,200-paragraph package, and ten single-character edits per position. Each timing includes native input, layout and view updates; it is not a general device-performance guarantee. Tests confirm the native text stays equal to the document and recovery succeeds.

| Edit position | First edit | Median of following nine |
|---|---:|---:|
| Before (end) | 173.8 ms | 110.2 ms |
| End | 51.3 ms | 38.7 ms |
| Middle | 81.7 ms | 74.3 ms |
| Beginning | 115.0 ms | 107.6 ms |

The optimized editor preserves containers before the page preceding the changed page. It verifies that preceding text and attributes match, and rebuilds conservatively for typography/style changes or font-fallback differences. Native invalidation begins at the reflowed page. PDF export always builds a fresh independent plan. Tests compare page ranges, line rectangles, continuation headers and footers against fresh layout after edits at multiple positions, Unicode additions, formatting, typography, undo and deletion.

End-of-script steady-state latency improved by about 65%. Middle and beginning edits remain slower; early-script reflow is the next performance target. There is no before measurement for the middle/beginning, so no speedup is claimed for those positions.

Live interface check: the multipage synthetic fixture opened with the compact toolbar, larger writing viewport, persistent Mode/Workspace bar, Document and Writing menus, and a readable help popover. The test package remained saved. The full verification suite passed 157 Swift tests, 37 Python tests and 14 self-tests.

## Retained TextKit layout and page zoom

The same release harness now measures:

| Edit position | First edit | Median of following nine |
|---|---:|---:|
| Beginning, immediately before this change | 126.9 ms | 109.0 ms |
| Beginning, retained layout | 88.6 ms | 76.9 ms |
| Middle, retained layout | 66.3 ms | 58.9 ms |
| End, retained layout | 48.9 ms | 39.8 ms |

Early-script steady-state latency decreased about 29% against the immediate baseline. One early keystroke still took 104.7 ms when text wrapping changed. End latency is approximately unchanged from the preceding 38.7 ms run; no end-of-script speedup is claimed. These are synthetic native input/layout/display-request timings, not hardware key-to-screen measurements. Benchmarks use 100% zoom; other zoom levels have correctness coverage, not performance measurements.

The editor retains TextKit containers and replaces only the changed attributed span. Matching Unicode-safe prefixes/suffixes permit native layout reuse when wrapping converges. Page rules still run from the preceding page, resetting container capacity before checking heading/cue grouping and dialogue continuations. Typography/style-only changes and mismatched prefix attributes use fresh layout. Unused trailing containers are removed after shrinkage. PDF export remains independent. Opt-in PACKAGE_BENCHMARK diagnostics report attributed-text preparation, cache setup and page-planning time without logging screenplay content.

Comparison tests include early dialogue growth and shrinkage that change page count, plus the prior Unicode, formatting, typography, undo and deletion cases. Zoom checks preserve document bytes, history, selection, native geometry and print page ranges at 50–300% and Fit Width across resized windows. All 158 Swift tests, 37 Python tests and 14 self-tests pass. Live checking of the synthetic multipage package verified 150%, Fit Width, typing/undo back to Saved, persistent controls during scrolling, and a scaled page-2 number and continuation cue.

Remaining performance work: full native line placement and attributed-text preparation still run for early edits; edits that change wrapping or typography can cause broader reflow. Avoid trading pagination correctness or input reliability for a benchmark improvement.


## Legacy JSON Script editor: incremental rendering — 2026-10-02

This section measures the legacy JSON Script editor, not the native-package editor described above. The isolated fixture contains 132 pages and 2,004 elements. Each Release run inserts 15 characters through WritingTextView, with the Document navigator hidden and the Pages pane available. Timing includes synchronous input, layout, run-loop draining and display requests; it is not hardware key-to-screen latency.

| Position / implementation | Median cycle | Maximum cycle |
|---|---:|---:|
| End, immediate valid baseline | 261.7 ms | 317.3 ms |
| End, incremental rendering | 153.5 ms | 200.1 ms |
| Middle, incremental rendering | 197.0 ms | 244.9 ms |
| Beginning, incremental rendering | 240.1 ms | 255.5 ms |

The comparable end median decreased about 41%. A preceding full-suite run measured 162.4 ms; run-to-run variation matters. No same-turn before measurement exists for the middle or beginning, so no improvement percentage is claimed there. Beginning-of-script edits still require broad reflow. Feature-length responsiveness is improved, not resolved.

The editor retains current paragraph attributed strings and replaces the changed paragraph interval, accounting for native text already inserted. Unchanged renders avoid text-storage writes. Cross-paragraph or unaccounted native changes use a full-render fallback. Global casing, typography, revision marks, element types and theme changes invalidate the relevant entries. Only the current document rendering is retained.

Unlocked pagination retains checkpoints before scene headings. It restarts at a heading strictly before the first changed source or displayed text, preserving the preceding completed pages and partial-page state. This respects heading/dialogue lookahead and catches earlier introduction casing changes caused by a later cue. It recalculates to the document end; suffix convergence is not implemented. Production-locked pagination and alternate pagination callers keep the full calculation path. Native layout invalidates from the earliest changed text/line coordinate while keeping full mismatch fallback. Text, document schema and save protection are unchanged.

Regression coverage compares cached pagination with a fresh model after edits, Undo/Redo, heading/type changes and global first-introduction casing changes. Native tests compare every rendered line position with a fresh page plan after beginning/middle/end edits, and compare incremental attributed text with a fresh rendering after Unicode edits, identical cross-paragraph paste, insertion/deletion and theme changes. Existing formatting, locks, save failures, recovery and navigation tests remain in the full suite.

The benchmark now selects WritingTextView explicitly: the first generic NSTextView can be the Pages field editor. Failed measurements that targeted that field are discarded. The viewport regression now awaits the observable navigation result, bounded to two seconds, instead of assuming a fixed 100 ms scheduling budget while native-window tests share the main actor.

Validation: Debug and Release each passed 202 Swift tests, 37 Python tests and 14 self-tests (253 checks). All three final benchmark runs passed. Evidence is retained in workspace `work/incremental-writing-2026-10-02/`. No new manual UI or notarization claim is made.


## Early-edit pagination convergence — 2026-10-02

Follow-up to the legacy JSON editor measurements above. Temporary instrumentation measured roughly 51 ms in pagination and 53 ms in native layout per beginning-of-script edit. Instrumentation was removed before final timings.

Pagination can now stop at an unchanged scene boundary when the remaining source/display text, page number, used height, and complete partial-page content/geometry/attributes match the prior calculation. Remaining pages and scene checkpoints are reused. This shortcut requires unchanged element count; insertions/deletions, nonconverging page-count changes, typography changes and production locks retain conservative forward/full calculation. Current-source maps are still rebuilt, so changed character offsets cannot be inherited from cached pages.

Unchanged editor refreshes also skip rebuilding the paragraph cache lookup. Native edit notifications still take the reconciliation path, including same-text cross-paragraph pastes. Pagination cache keys now distinguish absent typography from explicitly selected default typography because those take different attributed print paths.

A new regression compares reused pages, source spans, geometry, and PDF text/page count with a fresh model after early edits, Undo/Redo, page growth/shrinkage, global character introduction changes and default/changed typography. It asserts suffix reuse actually occurs for a converged edit and is bypassed when page numbering or typography changes. Saving and document format are unchanged. Native line-layout validation remains a separate cost and has not been relaxed.


Final isolated Release measurements on the same 132-page / 2,004-element fixture:

| Position | Previous median | Updated median | Updated maximum |
|---|---:|---:|---:|
| Beginning | 240.1 ms | 208.9 ms | 253.9 ms |
| Middle | 197.0 ms | 186.9 ms | 232.6 ms |
| End | 153.5 ms | 157.7 ms | 206.9 ms |

Beginning-of-script median improved approximately 13%; middle approximately 5%. End performance is roughly unchanged/slightly slower in this single-run comparison; no end improvement is claimed. A preliminary full-suite run measured 199.6 ms at the beginning, illustrating run-to-run variation. These synchronous harness timings still fall short of the desired writing responsiveness. Native layout and the rest of the synchronous editing path remain work to do.

Final Debug and Release each passed 203 Swift tests, 37 Python tests, and 14 self-tests (254 checks). All three final benchmarks passed. Evidence is retained under workspace `work/pagination-convergence-2026-10-02/`. No manual UI or notarization result is implied by these checks.


## Retained native wrapping validation — 2026-10-02

The legacy editor now retains an independent natural TextKit layout for wrapping validation. Changed rendered paragraph spans update that layout with current attributed text. The visible editor receives the validated page plan directly, eliminating its separate natural-coordinate layout pass. Natural TextKit can retain unaffected wrapping; the visible editor still validates all planned line starts and falls back to continuous layout when they disagree. No pagination validation is skipped.

The changed-span contract uses the new rendered range and total-length delta, accounting for native text insertion before the coordinator runs. Invalid ranges or unspecified differing content trigger a full validation-text refresh. Container width, padding, font-leading and default hyphenation settings follow the native editor. One additional current-document text/glyph layout is retained; memory usage has not been independently profiled.

Regression coverage compares incremental natural line starts with fresh independent TextKit layout through Unicode insertions, deletion, font changes, width changes, unspecified equal-length changes, trailing blanks and an empty document. Native page-coordinate checks now also exercise Undo/Redo and cross-paragraph replacement, comparing every planned native line with a fresh print plan. Existing page navigation, selection, typography, locks and save/recovery checks remain enabled. Authored content, file format and save behavior are unchanged.


Final isolated Release timings, same 132-page / 2,004-element fixture and 15-edit harness:

| Position | Previous median | Retained-validation median | Maximum |
|---|---:|---:|---:|
| Beginning | 208.9 ms | 180.4 ms | 210.7 ms |
| Middle | 186.9 ms | 164.7 ms | 209.6 ms |
| End | 157.7 ms | 155.4 ms | 210.8 ms |

Beginning and middle medians improved approximately 14% and 12%; end performance is effectively unchanged. These are single-run synchronous input/layout/display-request measurements, not hardware latency guarantees. The remaining 180 ms early-edit cycle still needs improvement; this change does not establish the desired writing responsiveness.

Final Debug and Release each passed 204 Swift tests, 37 Python checks and 14 self-tests (255 total). All three isolated benchmarks passed. Evidence is retained in workspace `work/native-wrapping-2026-10-02/`. No new manual visual review or notarization is claimed.

## Selective writing interface observation — 2026-10-02

Profiling the legacy JSON editor separated approximately 10–11 ms of document mutation and safe synchronous persistence from roughly 64 ms of synchronous editor rendering. The complete writing window incurred another substantial layout cost after the edit. Tests of narrower native invalidation and viewport sizing did not establish a useful improvement and were reverted.

The writing shell now observes an explicit presentation snapshot instead of every canonical model publication. Unchanged controls skip updates during ordinary text edits. The native editor continues observing the canonical model directly. The snapshot includes document identity/location, optional errors, save/recovery status, undo/redo availability, typography and emphasis, selection/type/revision/note indicators, current scene/page, page labels/navigation availability, zoom and theme. Actions and bindings always read and modify the current model; the snapshot is not a second authored document. Visible-page tracking keeps its independent observer.

Filtering applies only to Script mode with the document/context panels and modal workflows closed. Opening those panels, changing modes, or presenting title-page, command, or package workflows restores full observation. Notifications coalesce on the main queue after synchronous mutation/save completes. Native edits publish their completed presentation state before the next interface layout and cancel the redundant queued notification. This avoids a second deferred refresh after the immediate native render. Adding a displayed writing control requires adding its dependencies to the snapshot. Save behavior, history, source mapping, and document formats are unchanged.

New tests verify suppressed updates during ordinary typing alongside actual saved-file readback and Undo; refreshed formatting, errors, element types and structure; external-save conflict/recovery status; full observation outside the narrow writing case; and a native window that edits, switches modes, and returns to the same text.

The opt-in benchmark now yields to the main queue and performs layout again before requesting display. The previous nested run loop did not reliably drain deferred main-queue notifications. Preliminary numbers from the old harness are superseded. Comparisons below use the same corrected harness on the prior commit (`d423fa6`) and this implementation, in isolated runs. These are synchronous edit/layout/display-request cycles, not measured screen presentation latency.

Final isolated Release measurements, same 132-page / 2,004-element fixture and 15 edits per position:

| Position | Prior median | Updated median | Prior maximum | Updated maximum |
|---|---:|---:|---:|---:|
| Beginning | 178.4 ms | 87.4 ms | 236.0 ms | 268.7 ms |
| Middle | 169.5 ms | 75.3 ms | 323.2 ms | 344.6 ms |
| End | 158.8 ms | 64.7 ms | 305.5 ms | 332.3 ms |

Median cycles decreased approximately 51%, 56%, and 59% at the beginning, middle, and end. First-edit maxima remain worse than the baseline in these runs (approximately 21–33 ms higher), despite reducing the larger spike in the initial asynchronous-only implementation. Steady typing is substantially faster; startup/first-edit latency is not resolved. The under-50-ms target is not met. Open document/context panels retain the full update path and are not covered by this speedup claim.

Final Debug and Release each passed 209 Swift tests, 37 Python checks, and 14 self-tests (260 total). The six isolated before/after benchmarks passed. Evidence is retained in workspace `work/chrome-observation-2026-10-02/`. No manual visual review, measured display latency, remote publication, or notarization is claimed.
