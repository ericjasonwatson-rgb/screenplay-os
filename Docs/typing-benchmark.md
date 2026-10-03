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
