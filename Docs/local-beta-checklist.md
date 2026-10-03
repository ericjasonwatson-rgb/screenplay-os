# ScreenplayOS local review build 0.1.1

Build 2, October 3, 2026. macOS 13 or later, Apple Silicon. This local review build includes the measured native selection/navigation improvement. The architecture proposal is not implemented.

## Status

Ad-hoc signed; not Developer ID signed or notarized. It is a local development review build, not the downloadable team release. Apple enrollment is still pending according to the user. No bypass of macOS security settings is part of this checklist.

262 automated Release checks passed. No fresh manual installation review has been completed. Typical end-of-script typing remains about 67 ms in the benchmark; the under-50-ms goal is unmet. Navigation/setup remains about 208–213 ms in the measured end-of-script scenario.

## Review on copies of work

1. Import a copy of an FDX screenplay. Check title page, headings, dialogue and page navigation.
2. Type at the beginning, middle and end. Try both side panels open and closed. Note pauses, caret jumps or missing characters.
3. Apply bold, italic and underline, paste across paragraphs, then Undo and Redo. Confirm text and formatting return correctly.
4. Change zoom and navigate using the page list and scrollbar. Confirm the page indicator follows and clicking a page reaches it.
5. Save to a separate destination, close, reopen, and compare text, formatting and scene order.
6. Export using the available export/print controls. Inspect title page, dialogue continuations and page breaks in the resulting output.

Report the app version/build, macOS version, approximate script length, exact steps, expected result and actual result. Share a small nonconfidential reproduction when possible; do not include a full screenplay by default.

## Packaging

Use `SCREENPLAYOS_APP_VERSION=0.1.1 SCREENPLAYOS_BUILD_NUMBER=2` with `Scripts/package-app.sh` to reproduce this version label. The bundle also records its Git revision. No cloud services, accounts or automatic updates are introduced in this build.
