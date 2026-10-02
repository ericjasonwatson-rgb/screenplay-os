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
