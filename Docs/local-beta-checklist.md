# ScreenplayOS local review build 0.1.3

Build 5, October 3, 2026. macOS 13 or later, Apple Silicon. This local review build includes the native selection/navigation improvement and unchanged-paragraph render reuse. It also includes the clearer New menu, corrected title-page PDF layout, and an exact title-page export preview. The architecture proposal is not implemented.

## Status

Ad-hoc signed; not Developer ID signed or notarized. It is a local development review build, not the downloadable team release. Apple enrollment is still pending according to the user. No bypass of macOS security settings is part of this checklist.

265 automated Release checks passed for the retained source. Build 4 launched and its updated File menu was verified. Build 5 has not had a fresh manual launch/workflow check. On build 4, the user completed the manual FDX import, text/format editing, Undo/Redo, save/reopen, title-page and PDF-export checklist and reported that all worked. Automated control of the native file dialog remained unreliable; this manual result is user-reported, not an agent-observed end-to-end run. The ZIP was extracted and its ad-hoc signature verified. Build 5 source revision: `5ca9473`. This adds the verified scene navigator and shared-casing typing improvements. The most recent end-of-script test with both panels open measured about 79 ms median; the under-50-ms goal remains unmet. Six position/panel benchmark comparisons passed text-consistency checks. Median typing cycles range from 61–85 ms with panels closed and 98–116 ms with both panels open. All six medians improved versus the prior code, but maximum edit times were higher in three single-run comparisons. The under-50-ms goal is unmet. These are test-harness cycles, not physical display latency.

## Review on copies of work

1. Import a copy of an FDX screenplay. Check title page, headings, dialogue and page navigation.
2. Type at the beginning, middle and end. Try both side panels open and closed. Note pauses, caret jumps or missing characters.
3. Apply bold, italic and underline, paste across paragraphs, then Undo and Redo. Confirm text and formatting return correctly.
4. Change zoom and navigate using the page list and scrollbar. Confirm the page indicator follows and clicking a page reaches it.
5. Save to a separate destination, close, reopen, and compare text, formatting and scene order.
6. Export using the available export/print controls. Inspect title page, dialogue continuations and page breaks in the resulting output.

Report the app version/build, macOS version, approximate script length, exact steps, expected result and actual result. Share a small nonconfidential reproduction when possible; do not include a full screenplay by default.

## Packaging

Use `SCREENPLAYOS_APP_VERSION=0.1.3 SCREENPLAYOS_BUILD_NUMBER=5` with `Scripts/package-app.sh` to reproduce this version label. The bundle also records its Git revision. No cloud services, accounts or automatic updates are introduced in this build.
