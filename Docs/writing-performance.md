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
