# Final Draft pagination comparison — 2026-10-08

## Observed page counts

| Sample | ScreenplayOS | Final Draft 13 | Difference |
| --- | ---: | ---: | ---: |
| Defenders export (previous recorded baseline) | 18 | 15 | +20% |
| Synthetic action-heavy | 24 | 18 | +33% |
| Synthetic dialogue-heavy | 30 | 20 | +50% |

The two synthetic comparisons were read from the live apps. ScreenplayOS used the Release timing-audit build from source 53fa30a. The Defenders result is the earlier evidence in phase-a-fdx-export.md, not a newly repeated comparison. These are diagnostic samples, not a claim of universal pagination accuracy.

## Reproduction and integrity

The fixtures in AuditEvidence/pagination-2026-10-08 contain twelve scenes each. Action-heavy has eight long action paragraphs per scene (120 total elements). Dialogue-heavy has eight alternating speakers per scene, including parentheticals (252 total elements). Neither input had title pages, explicit page breaks, production locks, or custom layout settings. ScreenplayOS opened JSON imported by screenplay-inspect; Final Draft opened the corresponding FDX. The committed FDX files were saved by Final Draft to expose its default formatting. Every paragraph type and exact text was compared against the imported ScreenplayOS JSON after that save: both comparisons passed.

Final Draft settings: US Letter, 72-point top/bottom margins, Courier Final Draft 12, normal document leading, regular font leading. Action and scene-heading indents are 1.5–7.5 inches; dialogue is 2.5–6 inches. Space before is 24 points for headings, 12 for action/character, and zero for dialogue/parentheticals.

ScreenplayOS ScreenplayBodyLayout uses corresponding action/dialogue widths and paragraph spacing, but also sets lineSpacing to 2 points. PackageTypography resolves the document font through NSFont, with Courier fallback. Font metrics, line pitch, sentence splitting, and continuation handling require separate measurement; the extra spacing alone has not been established as the cause of the entire difference.

## Proposed next implementation

1. Measure baseline-to-baseline line pitch, wrapping, and usable page height using the same available font in both apps. Check action and dialogue separately, including split paragraphs and continuation lines.
2. Prototype explicit line pitch in a separate compatibility layout profile. Compare all three samples and screen/PDF output before selecting defaults. Do not apply a global percentage shrink to force these totals.
3. Preserve existing document layout and production locks. Require an explicit layout conversion with a page-change preview before applying a new profile to existing documents.
4. Add regression coverage for page boundaries, orphan headings, dialogue continuation, and renderer agreement once expected behavior has been measured.

No spacing, font defaults, or production-lock behavior changed in this audit.


## Line-pitch experiment — 2026-10-08

Added a read-only AppKit calibration harness at `Scripts/Diagnostics/measure-screenplay-lines.swift`. Run it with one or more FDX paths. `SCREENPLAYOS_REFERENCE_FONT` optionally points to a locally installed reference font; registration lasts only for the diagnostic process. No Final Draft font is copied into this repository or distributed.

The harness measured ten explicit lines and both saved fixtures at 12-point Courier and Courier Final Draft. Results are in `AuditEvidence/pagination-2026-10-08/line-calibration.txt`.

| Experiment | Measured baseline pitch | Action text height | Dialogue text height |
| --- | ---: | ---: | ---: |
| Current natural metrics + 2pt spacing | 16pt | 12,432pt | 14,280pt |
| Natural metrics without extra spacing | 14pt | 11,088pt | 12,936pt |
| Explicit 12pt minimum and maximum line height | 12pt | 9,504pt | 11,088pt |

Both fonts produced the same results in this harness, including 792 action-sample lines and 924 dialogue-sample lines. These are summed paragraph text heights, NOT page counts. They exclude paragraph gaps, continuation markers, keep-together rules, and page splitting. Final Draft's own rendered baseline pitch has not yet been measured; its font processed in AppKit does not establish its renderer's behavior.

A second independent constraint exists in `ScreenplayViewModel.pdfHeight`: every paragraph is clamped to at least 16pt. With the 12pt experiment, keeping that clamp increases the dialogue total from 11,088pt to 11,712pt. Therefore changing only paragraph lineSpacing cannot implement a consistent 12pt profile. The package editor also has a separate 14pt minimum in PackagePageGeometry and needs explicit parity coverage when a profile is integrated.

Validation: XML paragraph counts were cross-checked independently with Python ElementTree (120 action, 252 dialogue) for every font/mode; ten-line probes measured exactly 16, 14, and 12pt baseline spacing. The parser ignores nested metadata paragraphs in Final Draft scene properties. Application source, persistence, production locks, and installed builds were not modified. This is a diagnostic prototype, not an exposed compatibility option or a demonstrated Final Draft pagination match.

Next bounded integration: obtain a rendered Final Draft baseline measurement, then trial the selected pitch through the actual paginator, editor, and PDF projection together. Make paragraph minimum height and cache identity part of that profile; verify complete text coverage, continuation boundaries, zoom, and locked-document behavior before exposing conversion to users.


## Actual paginator experiment — 2026-10-08

Final Draft 13 exported the disposable dialogue fixture through Save As PDF (title page excluded). The output has 20 pages. On the first page, dialogue baselines are 12pt apart (129, 141, 153, 165, ... measured from the top). Character/paragraph gaps include 24pt. `final-draft-baselines.json` records the PDF hash and transformed baseline coordinates. `Scripts/Diagnostics/measure-pdf-baselines.py` reproduces the measurement with pypdf. The local reference PDF is retained in the workspace work/pagination-calibration-2026-10-08 directory, outside the source repository.

Added an internal, initializer-only `twelvePointExperiment` to the legacy filmmaking editor. It supplies explicit 12pt line height and paragraph minimum through the actual paginator, PDF renderer, editable text attributes, and printed editor placement. Print, pagination, measurement, and native render caches include the effective layout. The fitting-prefix minimum uses the same profile. Existing callers still select legacy layout; there is no preference, menu command, saved-format field, or document conversion.

Production locks and non-12pt document typography force legacy layout. Experimental instances cannot create production locks, because reopening a saved lock without its experimental profile would be unsafe. Package-editor layout is unchanged and is not part of this experimental integration.

| Sample | Default ScreenplayOS | 12pt experiment | Final Draft reference |
| --- | ---: | ---: | ---: |
| Action-heavy | 24 | 18 | 18 |
| Dialogue-heavy | 30 | 24 | 20 |
| Defenders pilot | 18 | 15 | 15 |

Counts exclude ScreenplayOS's separate exported title page. Matching two totals does not establish matching page boundaries or Final Draft compatibility. Dialogue remains different. Its current keep-together rule reserves an entire speech with its cue, while the next trial should assess keeping only the cue and the first required lines. Page-top paragraph spacing and continuation behavior also need isolated comparison. Do not alter the default or production documents based solely on these totals.

Validation: five new calibration tests cover source/file preservation, unmapped-fragment detection, PDF/script count agreement, native editor line positions at 80/100/125% zoom, render-cache profile changes, existing-lock fallback, non-12pt fallback, and rejection of experimental page locking. Full Debug and Release suites passed: 280 Swift tests, 37 importer checks, 14 self-tests per configuration. The Defenders sample was added to the comparison test before the Release run. Native views were hosted in test windows; this is not a manual typing or responsiveness benchmark.

Rendered visual checks covered the dialogue reference/candidate first pages and the candidate Defenders first/final script pages. The candidate PDF's measured adjacent dialogue baselines are 12pt. The extra space at the first heading and different page breaks remain visible. No installed app or notarized release was replaced.
