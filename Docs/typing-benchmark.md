# Native typing benchmark and app builds

The packaged app now defaults to Swift's optimized Release configuration. It remains a local development build, not a signed/notarized distribution. Use `SCREENPLAYOS_BUILD_CONFIGURATION=debug ./Scripts/package-app.sh` when a debugger-friendly package is needed. The chosen configuration is recorded in the bundle's ScreenplayOSBuildConfiguration property.

Tests default to Debug. To check optimized behavior:

```sh
SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh
```

To compare the configurations with a local monolithic screenplay JSON fixture:

```sh
./Scripts/benchmark-typing.sh /absolute/path/to/script.json
```

The opt-in test makes a temporary copy, uses isolated preferences and saves, and hosts the actual ContentView in a 1440 x 900 native window. It inserts 15 single characters at the document end. Each measurement includes synchronous insertion/autosave, layout, a short run-loop drain and display request. It checks agreement between the editor and model. It does not measure hardware key-to-screen latency or compositor presentation. Times are reported, never used as flaky pass/fail thresholds. The input file is not edited.

September 12, 2026: the 120-page fixture produced medians of approximately 120 ms in Debug and 98-100 ms in Release across two runs of each configuration. Individual pauses remained. This does not establish Final Draft parity or acceptable performance for all documents.

These results must not be compared directly with the earlier scratch harness's approximately 210 ms measurement: the harness uses a different hosting wrapper and test-process setup. The Debug/Release comparison uses the same current harness and unchanged editor implementation.

Experimental editor formatting/layout caches were removed because they did not consistently improve complete-window timings. The next investigation should use this optimized baseline to separate remaining native layout from surrounding SwiftUI work. Preserve text, selection, formatting, undo, save/recovery and printed output throughout.

## October 3, 2026: scene navigator refresh

Release, 132 pages / 2,004 elements / 204 scene headings, 1440 × 900 window, Navigator and Context Inspector open, end-of-document insertion, navigation settled before timing. Same 15-edit native-window harness. Each edit checks native text against the model; only an isolated temporary copy is changed.

The scene navigator previously rescanned all preceding paragraphs to number each heading, and repeated scene lookup, longest-scene calculation, and selected-scene lookup inside every row. Number headings in one pass and compute row lookup/count/selection values once per navigator refresh. No persistence, text-formatting, or pagination behavior changes.

| Run | Median typing cycle | Maximum |
| --- | ---: | ---: |
| Before | 98.0 ms | 114.1 ms |
| After | 85.6 ms | 100.3 ms |
| After repeat | 85.1 ms | 104.4 ms |

About 13% lower median in this workload. These are insertion/layout/display-request timings, not physical key-to-screen latency. The under-50-ms target is unmet. Beginning/middle positions and other documents are not established by this comparison. Full Release validation: 213 Swift tests, 37 Python checks, 14 importer self-tests passed. Evidence is in the workspace `work/typing-panels-2026-10-03/` logs and `timings.json`.

This source change is newer than the delivered 0.1.3 build 4 ZIP. The existing ZIP does not include it.

## October 3, 2026: rejected inspector refresh experiment

Tested filtering Context Inspector controls independently of its live selection header. The corrected implementation passed all 265 checks, including a new observation test, but the isolated same-workload median was 88.0 ms with a 122.4 ms maximum, compared with 85.1–85.6 ms and 100.3–104.4 ms maxima for the retained navigator optimization. An earlier experimental version was slower still. The full-suite benchmark is not a performance comparison because other tests run concurrently.

Removed the experiment and its experiment-specific test; retained application source is unchanged from `3cec0f6`, which passed 264 checks. Fewer refresh notifications did not translate into faster typing in this workload. Logs: workspace `work/typing-panels-2026-10-03/context-isolated.log` and `context-final.log`. Next profiling should focus inside synchronous native insertion/rendering rather than adding more observation filters without measured benefit.

## October 3, 2026: shared casing and ASCII coordinate spans

Opt-in `SCREENPLAYOS_TRACE_TYPING=1` now reports numeric input and render phase durations, with no document text or IDs. Input phases: reconciliation, model mutation, render, caret/scroll/chrome. Render phases: writing projection/string comparison, attributed paragraphs, geometry/print projection, page guides/layout-plan construction, native page-plan installation, selection/display invalidation. Tracing is off by default. These synchronous phases do not include the later SwiftUI layout/display pass.

Same 132-page, 2,004-element, both-panels-open, settled end-insertion Release workload: traced baseline 86.1 ms median / 105.8 ms maximum. Rendering accounted for 32.8 ms. ASCII spans alone reached 84.6 ms median; sharing the model's element-keyed casing cache with the writing projection reached 78.6 ms median / 93.2 ms maximum, with rendering at 25.8 ms. An untraced final run measured 79.3 ms median / 102.1 ms maximum. Evidence: workspace `work/typing-trace-2026-10-03/` logs and `results.json`.

ASCII capitalization preserves UTF-16 offsets, so one paragraph span suffices even with partial capitalization. Unicode retains expansion-aware spans. The shared casing cache compares current elements, including after edits and Undo/Redo. Tests cover every selection boundary of an ASCII fixture, partial name capitalization, Unicode, cached-versus-fresh projection after edits/Undo/Redo/typography, and the existing native editor and PDF suite. Full Release validation: 214 Swift + 37 Python + 14 self-tests = 265 passing checks.

The timing benefit is limited evidence for this workload, not a hardware latency claim or proof that the under-50-ms target is met. No updated app ZIP was built for this source change. The next measured targets are page-plan construction and remaining SwiftUI layout.

## October 3, 2026: page-plan attribute experiment

Tried reusing font/alignment attributes and the bridged writing string within page-plan construction. All 265 checks passed, but the traced median was 88.5 ms (maximum 109.3 ms), and the untraced repeat was 78.2 ms (maximum 105.0 ms). Against the retained implementation's approximately 79 ms result this does not establish a useful consistent gain. Removed the experiment. Evidence: workspace `work/page-plan-2026-10-03/`. Build 5 packages the retained source at `5ca9473`; it adds the verified navigator and casing improvements to build 4 without this experiment.

## October 4, 2026: beginning/middle/end validation

Build 5's retained source, Release, the same 132-page/2,004-element fixture, both panels open, 15 edits per position, navigation settled first. Tests edit temporary copies and check native/model text agreement after every edit. All five targeted runs passed, along with each runner's Python and importer checks. No application code changed.

| Position | Untraced median | Untraced maximum | Traced repeat median | Traced repeat maximum |
| --- | ---: | ---: | ---: | ---: |
| Beginning | 101.7 ms | 496.4 ms | 103.0 ms | 124.5 ms |
| Middle | 101.4 ms | 180.5 ms | 89.2 ms | 148.7 ms |
| End | 78.3 ms | 98.3 ms | — | — |

The 496.4-ms outlier occurred on edit 8 during synchronous insertion (415.3 ms), but did not recur in the instrumented repeat. Its root cause is unconfirmed. Do not discard it as noise or claim it fixed. In the beginning repeat's slowest cycle, native page-plan installation took 33.3 ms; the equivalent phase at the end previously took about 1 ms. This supports investigating layout of subsequent pages when earlier text changes, while preserving cursor positions, page breaks, and export consistency. A single outlier's phase does not establish the cause of all latency.

The beginning/middle results confirm that the end-only 79-ms measurement does not describe the whole script. No under-50-ms or sustained real-use claim is warranted. Logs and all samples: workspace `work/typing-positions-2026-10-04/`. The user still needs to exercise build 5 on a copy of a real screenplay; the reported manual writing workflow pass was build 4.

## October 4, 2026: demand-driven native layout

The native editor now explicitly resolves the visible viewport after installing its complete page plan, rather than forcing the entire text container to lay out on every edit. Full wrap validation and page-plan construction remain unchanged; TextKit resolves offscreen text when needed. Empty documents and trailing blank lines retain full immediate layout before placing the extra-line caret.

The first experiment failed `trailingBlankCaretUsesPrintedPagePosition` by 12 points. The explicit empty/trailing-newline fallback corrected it. Final full Release suite: 214 Swift + 37 Python + 14 importer checks = 265 passed. Existing native tests compare all line positions with a fresh plan after edits/Undo/Redo and cover page navigation, zoom, Unicode, print output and trailing blank caret placement.

Final isolated 132-page, both-panels-open, settled-navigation runs:

| Position | Prior median | Final median | Final maximum |
| --- | ---: | ---: | ---: |
| Beginning | 101.7 ms | 75.7 ms | 104.5 ms |
| Middle | 101.4 ms | 76.2 ms | 136.3 ms |
| End | 78.3 ms | 78.7 ms | 94.7 ms |

Earlier experimental runs also measured beginning/middle medians around 74–78 ms; one end run had a 326-ms outlier. The final repeat did not reproduce that pause. Neither that pause nor the previous 496-ms outlier is explained or claimed fixed. The under-50-ms goal remains unmet. These are 15-edit harness runs, not hardware latency or sustained real-user testing. Source changes have not been packaged into a new ZIP or manually reviewed. Evidence: workspace `work/viewport-layout-2026-10-04/`, including failed initial checks and successful `final-tests.log` and `*-final.log` runs.

## October 4, 2026: 100-edit runs and save/reopen verification

The opt-in native benchmark now accepts `SCREENPLAYOS_BENCHMARK_ITERATIONS` (default 15, supported 1–1000). After timing, it closes the model safely and opens the saved copy in a new model, comparing elements, typography, page labels and displayed text. This is an automated model reopen, not a manual quit/relaunch of the packaged app. No application behavior changed.

Build 6 application source, same 132-page fixture, both panels open, settled navigation, 100 edits per position:

| Position | Median | 95th percentile (nearest rank) | Maximum |
| --- | ---: | ---: | ---: |
| Beginning | 73.8 ms | 87.3 ms | 453.9 ms |
| Middle | 80.0 ms | 94.4 ms | 419.1 ms |
| End | 79.6 ms | 127.0 ms | 237.1 ms |
| Beginning, traced repeat | 73.3 ms | 96.4 ms | 122.2 ms |

All four runs passed per-edit native/model agreement and the save/reopen comparisons, plus the runner's Python and importer checks. At the untraced beginning maximum, insertion was 55.0 ms, immediate host layout 266.4 ms, and deferred layout/display 132.5 ms. The middle maximum spent 321.8 ms in immediate host layout. The large stall did not recur in the traced repeat; attribution within interface layout remains unconfirmed. Next isolate navigator versus inspector layout. This is not evidence that occasional stalls are fixed or a sustained human writing session passed.

Evidence: workspace `work/typing-long-run-2026-10-04/` logs and `results.json`. The application source is unchanged from build 6; only the benchmark and documentation changed.

## October 4, 2026: navigator observation isolation

Same source/workload as build 6, 100 edits near the beginning, 132 pages, Release, navigation settled. Baseline panel-isolation medians: neither panel 48.6 ms; navigator only 66.4 ms; inspector only 58.2 ms; both 73.1 ms. The navigator-only run included a 452.8-ms outlier. These separate runs are not additive cost accounting or proof of a stall's cause.

Filtered the sidebar container and navigator notifications by their displayed data: document metrics and identity, sidebar mode, scene identities/titles/order/counts, selected scene, characters and recent documents. Live detail panels retain full model observation; non-writing modes and sheets retain conservative full refresh. Canonical edits, persistence and layout are unchanged.

With both panels open, first post-change median was 61.4 ms (95th percentile 84.2 ms; maximum 119.1 ms). Repeat median was 60.6 ms (95th percentile 67.6 ms; maximum 87.1 ms). Baseline both-panel values were 73.1 / 83.2 / 150.9 ms. Typical typing improved about 16–17% in this scenario; tail measurements varied, so occasional stalls are not claimed fixed and the under-50-ms goal is unmet.

Full Release validation: 215 Swift + 37 Python + 14 importer checks = 266 passed. Added regression coverage for unchanged rows during typing, heading rename, paragraph counts, Undo and scene selection. Both 100-edit post-change runs passed per-edit native/model checks and save/reopen comparison. Evidence: workspace `work/panel-isolation-2026-10-04/`. This source change is newer than build 6 and has not been packaged or manually reviewed.
