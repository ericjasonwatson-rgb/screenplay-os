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

## First-edit and open-panel refresh scope — 2026-10-02

The first-edit trace on the 132-page fixture separated approximately 73 ms of native insertion from 190 ms of immediate host layout and 112 ms of deferred/final layout. The earlier presentation snapshot was too broad: a selection or Undo-availability change notified the complete writing shell and unrelated controls. With both the Navigator document panel and Context panel open, that snapshot also reverted all writing controls to full observation.

Writing presentation now has separate signals for the shell, workspace arrangement, toolbar commands, navigation controls, document identity, bottom status, writing page, page list, printed-page menu, and element-type picker. The toolbar is a separate `ToolbarContent` component. Each signal compares only the state that region displays. The document and context panels themselves continue observing the canonical model, so their contents remain live. Other modes and modal workflows retain conservative full refreshes. The default aggregate observer remains available for components without a narrower dependency contract.

No document, saving, history, pagination, or native text-layout code changed. Native edit completion still synchronizes the presentation state immediately. Region dependencies must be extended whenever a component begins displaying new model state; they are explicit selectors, not automatic property-read tracking.

Experiments with a native page list and further splitting the writing controls/page highlight did not improve the remaining delay and were reverted. Focus-mode measurements isolated a substantial deferred cost associated with the visible navigator, but did not prove its rows were the cause. Native tracing found inexpensive unchanged editor renders; it did not attribute the entire remaining host-layout cost. No unsupported claim of eliminating that cost is made.

The benchmark now reports three phases (native insertion, immediate host layout, deferred/final layout), supports independently opening the document and context panels, and can capture a fixture-only window image after timing. Each run still includes the first edit, followed by 14 more edits. Positioning the caret before timing does not settle a separate page-navigation gesture: the first edit can include scrolling to a distant caret. These are input/layout/display-request cycles, not physical key-to-screen measurements. Final comparisons use the same harness, fixture, 1440 × 900 window, and Release configuration; Focus mode is off and the page navigator remains visible.

| Document/context panels · edit position | Prior first edit | Updated first edit | Prior median | Updated median |
|---|---:|---:|---:|---:|
| closed-beginning | 289.7 ms | 211.5 ms | 87.6 ms | 86.4 ms |
| closed-end | 375.5 ms | 280.1 ms | 66.0 ms | 66.7 ms |
| panels-beginning | 302.7 ms | 247.3 ms | 217.5 ms | 120.9 ms |
| panels-end | 383.4 ms | 313.8 ms | 204.0 ms | 102.5 ms |

The first edit is also the maximum in each of these eight runs. First-edit cycles decreased approximately 18–27%. With both panels open, median cycles decreased approximately 44–50%; closed-panel steady typing is essentially unchanged. The remaining first-edit range is approximately 211–314 ms, and all medians remain above the under-50-ms target. These are isolated single-run comparisons; they do not establish tail-latency guarantees.

Debug and Release each passed 211 Swift tests, 37 Python checks, and 14 self-tests (262 checks). Added coverage verifies first-edit Undo availability without invalidating the shell, scoped controls with both panels open, save-conflict and recovery indicators, and native editing/Undo while both panels remain visible. Evidence is retained in workspace `work/first-edit-2026-10-02/`.

Captured editor/context layouts were inspected. Hosting-view image capture leaves the document sidebar blank in both the prior commit and the updated build; it cannot certify live sidebar rendering or native toolbar appearance. The comparison capture and its log are retained. No full live-app visual review or notarization is claimed.

## Separate navigation and typing measurements — 2026-10-03

The opt-in native benchmark now supports `SCREENPLAYOS_BENCHMARK_SETTLE_NAVIGATION=1`. It explicitly scrolls to the selected caret, performs host layout, yields to queued observation, and requests display before timing insertion. Navigation/setup time is reported separately. The default remains the previous combined workload for comparability. Intervals now use monotonic system uptime rather than wall-clock dates. No production editor code changed.

Three isolated Release runs per workload used the same 132-page / 2,004-element fixture, end position, 1440 × 900 window, document/context panels closed, Focus off, and page navigator visible:

| Workload | First input cycle across runs | Per-run median input cycle | First navigation/setup |
| --- | --- | --- | --- |
| Previous combined workload | 265.5–288.6 ms | 66.1–66.4 ms | Selection only; scrolling remains inside input cycle |
| Navigation given its own layout/observer turn | 76.1–80.4 ms | 66.1–66.6 ms | 275.1–280.0 ms |

This is not a product speedup. Moving navigation work before input changes the workload and does not reduce total navigation-plus-input time. It shows that the first-input spike is strongly sensitive to preceding selection/scroll/layout work; steady end-of-script typing remains approximately 66 ms and exceeds the under-50-ms target. A single queue turn is not a guarantee that every possible asynchronous activity has finished, and these measurements still do not measure physical screen presentation.

Next investigation: profile the navigation/selection host-layout path separately from native insertion, preserving page tracking and caret visibility. Do not hide the cost by prewarming during measured typing or remove required scrolling without native interaction coverage.

All six benchmark runs passed their native content-consistency checks; each invocation also passed 37 Python checks and 14 importer self-tests. The full Swift suite was not rerun for this benchmark-only change. Logs are retained under workspace `work/navigation-timing-2026-10-03/`. The StoryKit proposal remains separate and pending review.

## Publish native selection state before layout — 2026-10-03

A detailed navigation trace separated selection, native scroll, immediate host layout, queued work/final layout, and display request. One baseline measured approximately 4.3, 0.2, 53.4, 234.6, and 0.02 ms respectively. The deferred interval includes the deliberate queue yield; it does not attribute all time to one callback. Native scrolling itself was not the dominant measured cost. Eager page-list rows produced no useful improvement (282.5 ms navigation) and were reverted.

The native selection delegate now refreshes completed chrome state immediately after updating the canonical caret and selected element, matching the existing native typing path. This cancels the pending redundant chrome refresh and lets control changes participate in the immediate layout. It does not change scrolling, document content, persistence, or the native editor's canonical observation.

Three isolated Release runs with the same settled-navigation end-of-script workload measured first navigation/setup at 207.7, 212.2 and 212.8 ms, versus the preceding baseline range of 275.1–280.0 ms: approximately 23–26% lower. First input afterward measured 77.2–81.7 ms and median input 66.5–66.8 ms, effectively unchanged. Navigation is still visibly costly; no under-50-ms result or physical display-latency claim is made. Benefits at other navigation positions and open-panel combinations have not been benchmarked in this pass.

The native selection test now checks that the element-type presentation signal matches the new selection immediately, before a queue turn, and that the document is unchanged. The full Release suite passed 211 Swift tests, 37 Python checks and 14 self-tests (262 checks). Existing native scrolling/zoom/caret, typing, undo, layout and save/recovery coverage remained enabled. Debug and manual live-app inspection were not repeated. Evidence: `work/navigation-timing-2026-10-03/selection-refresh*.log`, `navigation-phases.log`, and `release-tests.log` in the workspace. No app installation or distribution was performed.

## Local review checkpoint — 2026-10-03

An experiment skipped replacing a native paragraph when its attributed contents already matched the canonical render. The settled end-of-script benchmark remained approximately 67 ms per typical edit, with no established benefit; the experiment was reverted. Log: workspace `work/native-redundant-edit-2026-10-03/end.log`.

The retained selection-refresh change passed a fresh full Release run: 211 Swift tests, 37 Python checks, 14 self-tests. This includes the native FDX import/edit/undo/save/reopen journey and existing formatting, export/print, conflicts and recovery tests. No new manual review or typing speedup is claimed. The under-50-ms typing goal remains open.

Packaging accepts optional `SCREENPLAYOS_APP_VERSION` and `SCREENPLAYOS_BUILD_NUMBER` numeric values, retaining previous defaults when omitted. Local review checkpoint: version 0.1.1, build 2. This is an ad-hoc signed development build, not a notarized distribution release. The StoryKit proposal remains pending review and outside this checkpoint.
