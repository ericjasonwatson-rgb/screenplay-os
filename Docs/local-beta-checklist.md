# ScreenplayOS local review build 0.1.3

Build 9, October 4, 2026. macOS 13 or later, Apple Silicon. This local review build includes the native selection/navigation improvement and unchanged-paragraph render reuse. It also includes the clearer New menu, corrected title-page PDF layout, and an exact title-page export preview. The architecture proposal is not implemented.

## Status

Ad-hoc signed; not Developer ID signed or notarized. It is a local development review build, not the downloadable team release. Apple enrollment is still pending according to the user. No bypass of macOS security settings is part of this checklist.

272 automated Release checks passed for source revision `e1f38a1`. Build 9 retains a proportional scene-planning lane and total estimated runtime range in Edit. Estimates are initially on for new preferences; an existing off preference is retained. The estimate display does not modify actual clip timing or playback. Media timing precedence is tested logic, not a complete media ingest/conform workflow. A manual measured-scene override is not implemented.

Native view rendering and scene-selection preservation passed. Packaged build 9 has not had an on-screen workflow review. The initial build 8 attempt was blocked by a locked Mac; subsequent UI connections timed out. Multiple app instances were listed, but a hang has not been established. The user's successful manual import/edit/format/Undo/Redo/save/reopen/title-page/PDF-export report applies to build 4. Build 7 previously had a direct panel-render check.

Build 9 keeps the sidebar mounted while the split view hides its column, and suspends invisible navigator display updates until reopening. This reduced the 30-cycle stress warning count from 15 to one during initial setup. The final 30-cycle run passed text and save/reopen comparisons without recurring table warnings during later cycles. The initial AppKit warning remains unresolved. See `ui-stress-review.md` for coverage and limitations.

A standalone 100-edit hidden-panel sample measured 47.3 ms median, 48.4 ms p95 and 72.6 ms maximum, in line with the earlier 48.6 ms median reference. This does not establish physical key-to-screen latency or eliminate occasional stalls.

The earlier navigator-redraw benchmark used 100 edits near the beginning with both panels open. Filtering unchanged navigator redraws reduced the median from 73.1 ms to 61.4 ms, with a repeat at 60.6 ms. Both runs passed save/reopen comparisons. These are harness measurements, not physical key-to-screen latency. The under-50-ms goal and occasional stalls remain unresolved. See `typing-benchmark.md` for the complete measurement history.

Build 9's priority manual check: repeatedly hide/show the navigator, edit a scene heading while it is hidden, and confirm labels/counts/selection are current on reopening. Also open Edit and enable Estimates. Confirm scenes have proportional lengths, the total/subtotal is labelled, and selection follows the script. Reorder scenes and check timing positions; turn Estimates off and back on. Then keep the navigator open while typing, then rename a scene, add/remove a paragraph, switch scenes, and Undo/Redo. Confirm scene labels, counts, and selection update. Also edit near the beginning, jump to later pages, check the final blank-line caret, and save/reopen a separate copy. No installed application was replaced by this packaging step.

## Review on copies of work

1. Import a copy of an FDX screenplay. Check title page, headings, dialogue and page navigation.
2. Type at the beginning, middle and end. Try both side panels open and closed. Note pauses, caret jumps or missing characters.
3. Apply bold, italic and underline, paste across paragraphs, then Undo and Redo. Confirm text and formatting return correctly.
4. Change zoom and navigate using the page list and scrollbar. Confirm the page indicator follows and clicking a page reaches it.
5. Save to a separate destination, close, reopen, and compare text, formatting and scene order.
6. Export using the available export/print controls. Inspect title page, dialogue continuations and page breaks in the resulting output.

Report the app version/build, macOS version, approximate script length, exact steps, expected result and actual result. Share a small nonconfidential reproduction when possible; do not include a full screenplay by default.

## Packaging

Use `SCREENPLAYOS_APP_VERSION=0.1.3 SCREENPLAYOS_BUILD_NUMBER=9` with `Scripts/package-app.sh` to reproduce this version label. The bundle also records its Git revision. No cloud services, accounts or automatic updates are introduced in this build.
