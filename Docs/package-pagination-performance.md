# Package print pagination and typing performance

The continuous minimal-package editor now offers Print Preview and PDF export. Writing remains continuous; pagination is an explicit derived snapshot, so it does not run on each keystroke or alter saved source data. Preview and export use the same generated PDF bytes. Package previews contain script pages without an invented title page. Existing legacy title-page and production-label display remains unchanged.

The first package print profile uses US Letter (612 × 792 points), a 432 × 648 point text area, left margin 108 points, top margin 72 points, 12-point Courier, and screenplay-type indents. TextKit lays out complete glyph ranges through successive page containers, allowing very long paragraphs to continue rather than clipping or dropping their remainder. Page numbers appear in the top margin. A heading, character cue, or parenthetical at the end of a page moves with following text; oversized blocks must still make progress. Text, authored casing, blank paragraphs, and IDs are not rewritten.

This is un-locked script pagination, not format conformance or production pagination parity. It does not add MORE/CONT'D dialogue markers, production locks, manual page breaks, title-page authoring, or pagination overlays to the writing surface. Rich packages remain read-only. The fixed print profile can differ from the adaptive on-screen layout.

## Performance change

Ordinary edits within one paragraph now use the existing validated string-replacement command directly, avoiding redundant whole-snapshot validation. The native text view already applied its character change; only the affected paragraph is restyled. Projection ranges update from the known change, and initial projection construction tracks UTF-16 offsets without repeatedly measuring an accumulating string. Structural edits, Undo/Redo, and external changes still rebuild their validated projection.

The benchmark hosts the actual PackageEditorView in a 900 × 700 native window, with recovery enabled, and inserts ten single characters at the end of a synthetic 1,200-paragraph script. The fixture contains three repeated sentences per paragraph and alternates headings/actions. Each timing includes insertion, layout, a short run-loop drain, and a display request. It validates agreement between native text and the package session, then flushes recovery. Sources and generated preferences are isolated.

Same-harness Release results, 2026-09-14:

| Measurement | Before | After |
| --- | ---: | ---: |
| Median insertion/layout/display request | 44.88 ms | 19.68 ms |
| Slowest of ten insertions | 59.33 ms | 33.41 ms |

The median fell approximately 56%. These are not hardware key-to-screen or compositor presentation measurements. One synthetic workload does not establish responsiveness for every script. Full JSON parsing and snapshot-based Undo remain costs; large-history memory and long-run typing coalescing are future work.

Run `PACKAGE_BENCHMARK=1 SCREENPLAYOS_BUILD_CONFIGURATION=release Scripts/test.sh --filter PackagePerformanceTests` to repeat. The test reports timings without hardware-dependent pass/fail thresholds.

## Verification

The full automated suite passed 109 Swift tests, 37 Python tests, and 14 self-tests. Print-specific cases cover a 35-page mixed-type document, contiguous complete character coverage, all 180 paragraph markers in extracted PDF text, US Letter page dimensions, empty text, a single very long paragraph, and heading/cue grouping. Source byte preservation, typing/selection, merge identities, Undo/Redo, save/reopen, and recovery tests also pass. Rendered first, middle, and final PDF pages were visually inspected for margins and text visibility.

Native app preview/export interaction is pending because the Mac was locked during the final on-screen check. Programmatic PDF generation and PDFKit decoding passed; this is separate from that pending interaction check.
