# UI stress review — October 4, 2026

Application source: `87afa6c`, packaged as 0.1.3 build 7. No application behavior changed during this review.

## Automated coverage

Two 30-cycle native ContentView runs passed on a disposable copy of the 132-page, 2,004-element fixture. Cycles combined 1000×700 and 1440×900 windows, navigator/inspector visibility changes, 75/100/150 percent zoom, beginning/middle/end edits, Unicode and newline insertion, Undo/Redo, bold, page navigation, and save/reopen comparisons. Native text matched model projections; saved elements and typography matched after reopening. Original fixture bytes were unchanged. Generated PDF data parsed and had at least the expected script page count; this was not a visual PDF review.

Reopening used a fresh model, not a process quit/relaunch. Automated operations are not physical keystroke latency measurements. The opt-in test is `longScriptUIStressWhenRequested`, enabled by `SCREENPLAYOS_STRESS_FIXTURE`; optional `SCREENPLAYOS_STRESS_CAPTURE_DIR` captures the first three layouts. Use `SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh --filter longScriptUIStressWhenRequested` with those environment variables.

The normal Release suite also passed: 216 Swift tests, 37 Python tests, and 14 self-tests (267 total). The opt-in stress body runs only when its fixture environment variable is supplied.

## Findings and limits

- Each run emitted 15 AppKit warnings: “Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.” No crash or assertion failure occurred. The root cause is unconfirmed; isolate rapid sidebar visibility/layout/selection changes before changing observation behavior.
- Narrow fixed-zoom views can require horizontal scrolling. The packaged app exposes a horizontal script scrollbar; overflow alone is not evidence of lost text. Manual review should assess how easy scrolling and zoom are to discover.
- One harness capture showed an empty navigator. A direct check of packaged build 7 with the existing short review document showed populated scenes and characters, a readable inspector, and intact text. The empty navigator was not reproduced there. Harness images alone cannot establish this as a product defect.
- Both panels were returned to their original hidden state after the packaged-app check. The review document was not edited.
- Prior measured typing stalls and the under-50-ms goal remain unresolved. These stress passes do not establish responsiveness parity or replace manual writing review.

Evidence stays locally in `work/ui-stress-2026-10-04/` at the workspace root: `stress.log`, `visual-stress.log`, `full-suite.log`, and three layout captures. Do not upload private-content fixtures or captures by default.

## Next review

Investigate the table reentrancy warning. Manual review can proceed on copies using build 7: sustained typing with both panels open, scene rename/add/delete and selection updates, zoom/page navigation, formatting and Undo/Redo, then save/close/reopen and export. Build 7 has had a direct panel-render check, not a complete manual workflow sign-off.

## Follow-up: initial scene planning lane

A controlled replacement of navigator row GeometryReader bars with ProgressView did not remove the warning: all 30 stress cycles passed, with the same 15 table-reentrancy warnings. The experiment was reverted. Root cause remains unconfirmed; do not describe the warning as fixed. Evidence: `no-geometry-stress.log`.

The subsequent Edit change adds a derived, time-proportional scene planning lane, total range/subtotal, explicit untimed gaps, and scene-specific media-duration precedence. It leaves persisted clip timing and playback unchanged. Unit coverage exercises edit order, cumulative positions, unknown scenes, rejected planned/omitted/invalid media timing, and model-preserving native lane rendering. The full media import/conform and manual measured-scene override workflow remains deferred.

Validation: 220 Swift tests, 37 Python tests and 14 self-tests passed (271 total). Native lane rendering preserved document content and playback duration while scene selection followed S002. Harness capture shows the intended 1:2 timed-width ratio and an explicit untimed block; packaged-app visual review is still required.

## Follow-up: stable navigator lifetime

The warning also reproduced 15 times in a 30-cycle run with `SCREENPLAYOS_STRESS_AUTOMATIC_LAYOUT=1`, which lets AppKit schedule layout instead of forcing it in the stress helper (`automatic-layout-stress.log`). Forced harness layout is not a sufficient explanation.

ContentView previously removed the sidebar contents while also asking NavigationSplitView to hide its column. Keeping SidebarView mounted and leaving visibility to NavigationSplitView reduced the warning to one during initial setup, before the first cycle. Both automatic and original forced-layout runs passed all 30 cycles, with no repeated table warnings during later cycles (`stable-sidebar-stress.log`, `stable-sidebar-forced-stress.log`). This is a reduction in repeated warnings, not a complete resolution of the initial warning.

The on-screen connection to build 8 timed out twice; the app inventory showed multiple ScreenplayOS instances. That does not prove an app hang. No instances were force-quit and no user documents were edited. Packaged-app visual review remains pending.

The final implementation also freezes sidebar/navigator display signals while the column is hidden, then captures current data when reopened. A regression test verifies that hidden scene-name/structure edits refresh on reopening. The full Release suite passed 221 Swift, 37 Python and 14 self-tests (272 total).

Separate 100-edit beginning-of-script samples: keeping the sidebar mounted without the hidden-update guard measured median 52.9 ms hidden / 58.2 ms both panels open. With the guard, the hidden-panel sample measured median 47.3 ms, p95 48.4 ms and max 72.6 ms, versus the earlier hidden-panel reference median 48.6 ms. These samples provide no evidence of a hidden-panel slowdown after the guard; they do not prove hardware input latency or eliminate occasional stalls. The benchmark invoked during the full suite is not used for performance comparison because other tests shared that run.

Final guarded implementation: original forced-layout stress passed another 30 cycles with one initial table warning and no recurring warnings during later cycles (`stable-sidebar-gated-stress.log`).

## Startup isolation and live-session check — October 4, 2026

Build 9's UI connection timed out again, including a lookup by application name. Finder responded normally. Activity Monitor eventually opened and showed seven ScreenplayOS processes, with low CPU at observation time and none labelled Not Responding. This does not prove that duplicate instances caused the timeout or that every app window is healthy. The user was asked to save and quit the open copies before a single-copy review. No ScreenplayOS process was force-quit, no user document was edited, and application behavior was not changed during this pass.

Four standalone synthetic SwiftUI probes completed six resize cycles each without the table-reentrancy warning: plain sidebar List; NavigationSplitView with a text editor; hidden/custom list background; and nested scene-row views with custom row backgrounds. They did report sandbox/host-service connection messages. These probes narrow the reproduction but do not clear the real startup warning or establish its root cause. Reproducer source and logs are local in `work/startup-warning-2026-10-04/` at the workspace root. Build 9 remains the current review artifact; a new package is unnecessary for documentation-only findings.

## Cleanup and clean launch — October 4, 2026

After the user quit all copies, 11 obsolete targets were removed: builds 7/8 ZIPs and checklists, staged builds 5–8, the build-4 review app, and the two obsolete user-Applications bundles. macOS blocked shell removal of the installed bundles even with requested filesystem access; Finder moved them to Trash. Source, documents and Git history were retained. Build 9 was installed at `~/Applications/ScreenplayOS.app`; its ad-hoc signature verified, and the retained ZIP hash was unchanged. Cleanup receipt: `work/build-cleanup-latest-2026-10-04.json`.

Finder launched the replacement. The app inventory then showed one running ScreenplayOS instance. CUA rejected the installed app path, display name and bundle ID as Invalid app, including after a REPL reset. Therefore the packaged visual review remains unverified; the tool error does not establish an application defect. No code or document edits were made in this cleanup pass.
