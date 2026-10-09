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


## Speech flow and page-top trials — 2026-10-08

Two additional internal variants isolate the causes instead of replacing the baseline experiment. `twelvePointFlowExperiment` keeps a character cue and any parenthetical with the opening two dialogue lines plus room for MORE, rather than reserving the entire speech. The existing continuation path then splits the remaining speech. `twelvePointPageTopExperiment` adds suppression of space-before at a page start, including generated continuation cues and paragraphs moved to the next page. Mid-page paragraph gaps remain unchanged.

| Sample | 12pt only | Speech flow | Speech flow + page-top spacing | Final Draft reference |
| --- | ---: | ---: | ---: | ---: |
| Action-heavy | 18 | 18 | 18 | 18 |
| Dialogue-heavy | 24 | 21 | 20 | 20 |
| Defenders | 15 | 15 | 15 | 15 |

These remain initializer-only experiments. Defaults, installed releases, saved documents, and package-editor layout are unchanged. Existing page locks and non-12pt typography use legacy geometry. No new document setting or conversion has been introduced.

The new checks concatenate every source element's printed fragments and compare exact text against the default renderer, reject page heights above 648pt, reject stranded cues/parentheticals in these samples, pair MORE with the following continued cue, and check zero top spacing in the combined variant. Native editor positions at three zooms are now checked using the combined variant. All experimental variants are checked against existing-lock and 14pt-font fallback.

Rendered review covered the combined dialogue variant's first three script pages, including a split speech with MORE and CONT'D. The complete dialogue PDF text matches the Final Draft reference after excluding generated page numbers/continuation lines and whitespace; hashes and normalization are recorded in `flow-comparison.json`. Only the first of the twenty corresponding pages has identical normalized text. Matching total page counts therefore does not mean matching page boundaries.

A remaining measurable variable is horizontal placement. In the reference first heading, Final Draft explicitly positions adjacent non-space glyphs 7pt apart (14pt across a space), although the embedded 12pt font has a nominal 7.2pt advance. See `character-advance-observation.json`. The observed grid must be tested separately from font choice; it is not evidence that all fonts, sizes, or Final Draft documents should be forced to this grid. Sentence-boundary splitting may also affect page breaks.

Next: test horizontal advance and sentence-boundary behavior against rendered references, including richer typography, before deciding on a document-level compatibility option. Do not expose or persist these experiments as production layout yet.

Validation completed: full Debug and Release runs each passed 281 Swift tests, 37 importer checks, and 14 self-tests (332 checks per configuration). Build/test logs are retained with the local calibration artifacts. No signing, installation, or release publication was performed.


## Character grid and continuation-footer trials — 2026-10-08

`sevenPointGridExperiment` adds a measured 7pt character advance to the previous page-top/flow candidate. It is limited to the document's 12pt Courier setting; other font families, sizes, and existing locks use legacy layout. Kerning is calculated from the installed Courier font's actual advance rather than assuming it is exactly 7.2pt. The same attributes reach pagination, PDF drawing, native text storage, and the printed editor plan. A native glyph-position test checks the advance to within 0.001pt.

The reference's first dialogue page now has identical trimmed lines, but matching wrapping alone did not change the full-page boundary comparison. On reference page two, Final Draft's last body baseline is 717pt from the top and MORE is at 728pt, below the body region. ScreenplayOS previously reserved one body line for MORE.

`footerContinuationExperiment` adds a separate trial: keep the full 648pt body area for source text and permit a generated MORE marker in the following 12pt footer area. The checks distinguish body height from footer height and still pair MORE with the next continued cue. This variant also removes the PDF renderer's extra 4pt drawing-rectangle height; measured body baselines on the first dialogue page then match the reference exactly (starting at 81pt), as do its line breaks. Visual review covered the following two continuation pages and found no clipping or overlapping text.

Both new variants retain the measured 18/20/15 page counts. `grid-footer-comparison.json` records hashes, full text equality after excluding generated markers/whitespace, first-page line equality, and the baseline comparison. The remaining nineteen page boundaries still differ. In the inspected split speech, Final Draft stops after the sentence ending “train arrives.” whereas the candidate continues with the remaining words that fit on that line.

The remaining sentence-boundary rule must be coordinated with native text layout. `fittingPrefix` currently uses the original paragraph's natural line boundaries so the editable view and print fragments align. Cutting arbitrarily at punctuation can produce fragment starts the native editor does not lay out as line starts; a matching page count or PDF-only fix would not be sufficient. This trial does not introduce sentence-aware splitting.

Tests additionally verify PDF text character coverage on every generated page in all trial variants, source order through exact fragment concatenation, native line positions at three zooms, and non-Courier fallback. PDFKit sometimes spatially reorders right-aligned transitions and page numbers, so its coverage test compares normalized character multiplicities per page; ordered text equality is separately checked through pypdf against the dialogue reference. No proprietary font is bundled or copied. No compatibility setting, migration, app installation, or release publication is included.

Validation: full Debug and Release each passed 282 Swift tests, 37 importer checks, and 14 self-tests (333 checks per configuration). Logs and generated PDFs remain in the local calibration work directory.

## Sentence endings aligned to native lines — 2026-10-08

Added `sentenceAlignedLineExperiment`, an initializer-only extension of the footer trial. For overflowing dialogue it prefers the latest Foundation sentence boundary that also equals a fitting native line end, leaving at least two lines in the preceding fragment. If none qualifies, the existing natural-line split remains. The splitter uses UTF-16 offsets and returns a prefix of the original text, including whitespace. It neither inserts a newline nor changes source text. Action splitting is unchanged. This is a conservative sentence preference, not a full implementation of Final Draft's sentence-breaking setting.

The comparison is negative: none of the three existing reference samples changes its page boundaries versus the footer trial. Counts remain 18/20/15, and only dialogue page one matches the Final Draft reference boundary. Full normalized dialogue text remains equal. `sentence-aligned-comparison.json` records this result and PDF hashes. The inspected Final Draft boundary falls inside a naturally wrapped line; this trial deliberately cannot reproduce it.

A synthetic dialogue stress case exercises actual backtracking: its printed fragments must differ from the footer trial, while native editable line positions match the print plan at 80/100/125 percent zoom. Selecting every planned line start preserves its source offset and leaves the document unchanged. Unit checks cover the two-line minimum, a sentence ending inside a line, empty capacity, Unicode UTF-16 positions, and whitespace preservation. The existing corpus checks cover source concatenation, PDF character coverage, body/footer limits, paired continuation markers, and locked/non-Courier/non-12pt fallback for the new profile.

Do not promote this profile or claim improved Final Draft parity. The next bounded task is a layout-only mechanism for an interior sentence break, with cursor hit-testing, selection, typing, Undo, and continuation reflow tests before connecting it to pagination. The native wrapping guard remains intact. No installed app, release archive, persisted layout preference, or document schema changed.

Validation: full Debug and Release suites each passed 284 Swift tests, 37 importer checks, and 14 self-tests (335 checks). A subsequent test-only refinement retains the original footer native-layout case alongside the synthetic sentence case and isolates its reference model's preferences; focused Debug and Release calibration runs verify that refinement. Native offset selection is not a mouse hit-testing or manual typing benchmark, and the interior-line behavior remains unimplemented.

## Interior sentence breaks with native editing — 2026-10-08

Added the internal `sentenceBoundaryExperiment`. Overflowing dialogue can now end at the last fitting sentence boundary even when that boundary lies inside a naturally wrapped line. It keeps at least two lines before the break and requires a space-delimited word boundary. No canonical character, hidden newline, attachment, or glyph substitution is inserted. The earlier conservative trial remains available for comparison.

The print plan supplies allowed line starts for split dialogue paragraphs only. Both the visible editor and its separate wrapping validator use the same policy through AppKit's word/hyphen break delegate callbacks. TextKit backs up to an allowed break opportunity. The existing plan-validation guard remains: incompatible layouts fall back instead of mixing printed and natural coordinates, and the experimental constraints are cleared on rejection. Policy changes invalidate layout in both managers. Ordinary paragraphs and default layouts retain natural wrapping. This uses the documented [NSLayoutManagerDelegate line-break hooks](https://developer.apple.com/documentation/appkit/nslayoutmanagerdelegate); their SDK contract says refusing a word break searches for an earlier opportunity.

Reference results: counts remain 18/20/15 for action/dialogue/Defenders. Full normalized dialogue text is equal, and corresponding script pages **one and two** now have equal normalized text boundaries (previously only page one). Page two ends after “train arrives.” and resumes “The room is quiet” on page three. Sixteen dialogue page boundaries differ from the footer-only candidate; action and Defenders boundaries are unchanged. `interior-sentence-comparison.json` records hashes, normalization, and matching pages. Matching two pages is not Final Draft parity.

Rendered checks cover candidate script pages two and three and reference page three. There is no visible clipping or overlap at the inspected split. The next discrepancy is measurable: on reference page three the continued-character cue is above the normal body start, whereas this candidate still uses a body line for that cue. The JSON records the top baselines. Header continuation placement needs its own bounded trial before attributing the remaining eighteen page mismatches to other causes.

Native checks cover original and synthetic dialogue at 80/100/125 percent zoom, every planned line's actual position, mouse hit positions, selection across a page break, Unicode replacement, deletion of the boundary space, and Undo/Redo with exact element restoration. Copy verification uses a disposable private pasteboard and the text view's advertised types; enable it with `SCREENPLAYOS_TEST_PASTEBOARD=1` in a macOS process that can reach the pasteboard service. The filesystem sandbox blocks even a plain pasteboard write. Test setup was corrected to distinguish rendering-only byte preservation from intentional autosave of a disposable editing fixture; the checked-in FDX fixtures remain byte-identical in both cases.

This remains initializer-only: no UI preference, saved-format change, migration, production lock creation, installation, signing, or release publication. Existing locks, non-12pt typography, and non-Courier fonts use legacy geometry. Large-document responsiveness and richer typography still need assessment before enabling the candidate for normal use; a changed break policy currently invalidates the full native layout.

Validation: full Debug and Release each passed 286 Swift tests, 37 importer checks, and 14 self-tests (337 checks per configuration), with private-pasteboard copying enabled. Final focused Debug and Release calibration runs passed all 11 tests after adding the Objective-C delegate's main-actor compatibility annotation and limiting split-paragraph bookkeeping to the new profile. The introduced delegate-conformance warning is resolved; pre-existing test/SDK warnings remain. Logs and rendered PDFs are retained under the local calibration work directory, with this trial's PDFs in `interior-sentence/`.

## Continued-character cue in the top margin — 2026-10-08

Added the internal `headerContinuationExperiment`, extending the sentence-boundary trial. A generated, single-line continued-character cue is placed 13pt above the first body baseline, matching the measured 68pt reference baseline while body text begins at 81pt. Its layout uses -13pt before, 12pt text height, and 1pt after, giving zero body-height contribution. PDF drawing and native placement consume that same layout. Only generated cues at the page start receive this treatment. Cues that wrap beyond one line retain the existing body placement so long names do not clip into the top margin.

The dialogue comparison now matches **all 20 corresponding pages** for normalized source-text boundaries, trimmed body lines, and body text plus baseline coordinates. Full normalized source text remains equal. Script-page counts remain 18/20/15 for action/dialogue/Defenders. `header-continuation-comparison.json` records PDF hashes, the exact normalization, matched pages, and generated-marker coordinates. This establishes alignment for the generated dialogue reference, not universal Final Draft compatibility or pixel-identical output. Generated cues use a straight apostrophe rather than the reference's curly apostrophe, and MORE remains at 729pt versus the reference's 728pt.

Rendered inspection covered candidate script pages three and four, including a header continuation and a footer continuation. No clipping or overlap was observed there. Native tests exercise the new profile at 80/100/125 percent zoom, mouse hit positions, copying across a page break, Unicode editing, boundary-space deletion, and Undo/Redo. A dedicated geometry test checks the zero-height header contribution and first body-line position. Its long-name variant deliberately uses overflowing dialogue and verifies that a multiline cue consumes body space instead of moving into the margin; the original shorter fixture happened not to split after replacing its names and did not exercise that fallback.

Existing-lock, non-Courier/non-12pt fallback, and rejection of new experimental production locks also cover this profile. This trial does not change the default layout or saved document format, and does not install or publish an app. Next: stress the candidate with varied real-script structure, rich text, and long-document editing latency before deciding whether to expose a compatibility setting. The remaining one-point footer-marker offset is separately measured and does not affect the matched body pagination.

Validation: full Debug and Release each passed 287 Swift tests, 37 importer checks, and 14 self-tests (338 checks), with private-pasteboard copying enabled. Separate release/packaging work appeared in the shared checkout during validation. An isolated snapshot of commit `589d13f` plus only the six pagination files was therefore compiled independently and passed the full 338-check Debug suite as well. The pagination commit excludes that concurrent work, including its separate initialization change in ScreenplayViewModel. Logs and rendered artifacts are retained in the local `header-continuation/` calibration directory.


## Candidate editing stress and incremental wrapping — 2026-10-08

The internal candidate passed the existing 30-cycle native UI stress workload on the Defenders fixture: window resizing, 75/100/150 percent zoom, navigator/context visibility, Unicode edits, bold formatting, Undo/Redo, page navigation, save/reopen, PDF export, and unchanged original fixture bytes. `SCREENPLAYOS_STRESS_LAYOUT=header` now selects the candidate only inside the benchmark/stress tests, including reopened models; an assertion prevents silent fallback from being counted as candidate coverage. Omitted selection preserves legacy tests; unknown values fail.

Long-script profiling found a regression in page-plan installation. Every changed dialogue-break policy previously discarded all retained wrapping and invalidated the entire displayed layout. Policies now retain only relevant split-dialogue starts, use binary search for paragraph membership, and identify the earliest potentially changed paragraph. The validator keeps the unaffected prefix and rebuilds the affected suffix; the editor also limits invalidation to the earliest changed text, coordinates, or break policy. A regression test compares retained and fresh layouts through policy-only changes, insertions/deletions, paragraph splits, Unicode, bold text, resizing, and empty content. Ordinary unsplit wrapping and the default profile remain unchanged.

On the same disposable 2,004-element fixture, 15 middle-position Debug edits had median latency of **256.7 ms before and 144.8 ms after** (44 percent lower). Current legacy was 74.1 ms. Sequential Release measurements of the final code were:

| Typing position | Legacy median | Candidate median | Candidate maximum |
| --- | ---: | ---: | ---: |
| Beginning | 49.9 ms | 159.7 ms | 167.7 ms |
| Middle | 52.0 ms | 112.3 ms | 123.5 ms |
| End | 55.8 ms | 57.1 ms | 65.6 ms |

Each run used settled navigation, 15 edits, hidden navigator/context, and the same 1440×900 native host. Legacy paginates this fixture to 132 script pages; the candidate to 99. Timing includes insertion, layout, and deferred display. These are single-Mac observations, not hardware-independent guarantees or a Release before/after comparison. Raw samples and the fixture hash are in `header-stress-performance.json`; local logs are under `work/pagination-calibration-2026-10-08/header-stress/`.

The candidate remains disabled by default. Correctness checks passed, but beginning/middle editing is still slower than legacy. Next investigate rebasing unchanged downstream break offsets across edits so offset shifts alone do not invalidate the suffix, then repeat the same workloads. This change does not alter PDF pagination, canonical text, file format, locks, installation, or distribution.

Validation: the isolated snapshot passed full Debug and Release suites: 288 Swift tests across 47 suites, 37 importer checks, and 14 self-tests (339 checks per configuration). The Debug suite additionally enabled the 30-cycle candidate UI stress workload. Existing calibration tests cover the exact native line geometry and cross-page editing; private-pasteboard copying was not re-enabled for these runs. The six long-script Release benchmark runs also passed save/reopen assertions. Source changes were transferred only into the five owned source/test files, excluding concurrent release/distribution work.
