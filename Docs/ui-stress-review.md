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
