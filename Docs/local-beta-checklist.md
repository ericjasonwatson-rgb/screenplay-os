# ScreenplayOS local review build 0.1.3

Build 6, October 4, 2026. macOS 13 or later, Apple Silicon. This local review build includes the native selection/navigation improvement and unchanged-paragraph render reuse. It also includes the clearer New menu, corrected title-page PDF layout, and an exact title-page export preview. The architecture proposal is not implemented.

## Status

Ad-hoc signed; not Developer ID signed or notarized. It is a local development review build, not the downloadable team release. Apple enrollment is still pending according to the user. No bypass of macOS security settings is part of this checklist.

265 automated Release checks passed for source revision `2e640dc`. Build 6 includes the navigator and shared-casing optimizations plus deferred offscreen native layout. The extracted ZIP's ad-hoc signature verified. No fresh manual launch or end-to-end workflow review has been completed for build 6. The user's successful manual import/edit/format/Undo/Redo/save/reopen/title-page/PDF-export report applies to build 4.

In the 132-page, both-panels-open benchmark, final medians were 75.7 ms at the beginning, 76.2 ms in the middle, and 78.7 ms at the end. These are 15-edit insertion/layout/display-request measurements, not physical key-to-screen latency. The under-50-ms goal is unmet. Isolated stalls seen in earlier runs have not been explained or claimed fixed. See `typing-benchmark.md` for evidence and limitations.

Build 6's priority manual check: edit near the beginning, jump to later pages and back, then confirm caret placement and page breaks. Test a final blank line, Undo/Redo, zoom changes, save/reopen, and PDF export on a separate copy.

## Review on copies of work

1. Import a copy of an FDX screenplay. Check title page, headings, dialogue and page navigation.
2. Type at the beginning, middle and end. Try both side panels open and closed. Note pauses, caret jumps or missing characters.
3. Apply bold, italic and underline, paste across paragraphs, then Undo and Redo. Confirm text and formatting return correctly.
4. Change zoom and navigate using the page list and scrollbar. Confirm the page indicator follows and clicking a page reaches it.
5. Save to a separate destination, close, reopen, and compare text, formatting and scene order.
6. Export using the available export/print controls. Inspect title page, dialogue continuations and page breaks in the resulting output.

Report the app version/build, macOS version, approximate script length, exact steps, expected result and actual result. Share a small nonconfidential reproduction when possible; do not include a full screenplay by default.

## Packaging

Use `SCREENPLAYOS_APP_VERSION=0.1.3 SCREENPLAYOS_BUILD_NUMBER=6` with `Scripts/package-app.sh` to reproduce this version label. The bundle also records its Git revision. No cloud services, accounts or automatic updates are introduced in this build.
