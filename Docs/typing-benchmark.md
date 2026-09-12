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
