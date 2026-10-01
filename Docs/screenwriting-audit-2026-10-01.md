# Screenwriting audit against Final Draft

Date: 2026-10-01. ScreenplayOS implementation reviewed: `2be428f`.
Reference application: installed Final Draft **13.4.0 Build 120**, macOS.

## Follow-up status

The first repair is implemented in [FDX import verification](fdx-import.md):
default import rejects dual dialogue, and the Mac app offers an explicitly
reviewed sequential conversion that retains both speeches. The audit evidence
below remains the historical reproduction at `2be428f`. Native acceptance and
separate saving now pass in the packaged release; the earlier isolated test
instance timeout remains undiagnosed.

F02 is partially repaired: the legacy writing surface and script-body PDF now
both resolve the document typography, defaulting to regular Courier 12. Explicit
font choices and inline emphasis remain authoritative. Zoom scales screen text
only; viewing does not upgrade the document format. A subsequent bounded repair
shares legacy element widths, indents, paragraph spacing, alignment, and line
spacing between the continuous editor and PDF. This corrects the editor's wider
transition column, extra four-point paragraph gaps, and missing General spacing.
See [body-layout verification](screenplay-body-layout.md). Pagination, title
page templates, and the two writing engines still need alignment. Existing
unstyled PDFs may wrap differently after replacing the system monospaced font;
this repair does not establish page parity. Other findings remain open.

## Verdict

ScreenplayOS is a working writing prototype, **not yet a dependable Final Draft replacement**. Its editor safety work, native selection, undo, recovery, basic formatting, and PDF output are useful foundations. They do not establish screenwriting parity. Pause new Edit/Boards/media features until the writing release gates below pass.

The most urgent finding is actual text omission on FDX dual-dialogue import. The next is inconsistent writing/print geometry. A writer must be able to trust every word, the page they are editing, and the document they send to someone else.

This is a broad feature-family audit with source inspection and targeted native verification, not a claim that every Final Draft command, template, font, or edge case has been exhaustively exercised. “All features” is a coverage inventory to maintain; it is not a useful single completion claim. macOS desktop is the reference, not Final Draft Cloud, Go, or Windows.

## Evidence and method

- Inspected the installed application's File, Edit, Format, Insert, Document, Tools, and Production menus, element settings, default font, and dialogue margins. Merely seeing a command establishes its presence, not its reliability.
- Created a disposable screenplay inside Final Draft, made its two speeches dual dialogue, and saved the FDX. No existing user screenplay was edited.
- Ran that file through ScreenplayOS's current `screenplay-inspect` importer. Reproduced missing text. Preserved a minimal fixture and machine-readable result in [AuditEvidence](AuditEvidence/fd13-dual-dialogue-result.json).
- Inspected both ScreenplayOS writing implementations, package admissibility rules, persistence adapters, print engines, imports, menus, and tests.
- Reran `Scripts/test.sh`: **173 Swift tests + 37 Python checks + 14 executable checks passed**. Log: `work/screenwriting-audit-tests-2026-10-01.log` in the enclosing workspace. The new dual-dialogue probe fails separately and is not counted among those passing tests.
- Reviewed official Final Draft documentation linked below. The large downloadable Mac manual could not be retrieved by the web reader; this report does not claim a complete manual read.
- Did not rerun long-session typing benchmarks, test every printer, simulate power failure, inspect every existing screenplay, or certify accessibility. Older benchmark results remain historical.
- Application source and release app were not changed by this audit.

## Prioritized findings

### F01 — P0: FDX dual dialogue silently loses authored text

**Reproduced.** Final Draft writes a `DualDialogue` container inside a top-level `Paragraph`, with nested character/dialogue paragraphs. `FDXImporter.swift:138` accepts only direct `FinalDraft/Content/Paragraph` records, and its text-depth guard accepts only direct Text children. It therefore creates an empty General element for the wrapper and ignores both speeches. Generic layout warnings do not identify the missing material.

Reference input contains `ALICE`, `AUDIT LEFT WORDS.`, `BOB`, and `AUDIT RIGHT WORDS.`. All four strings are absent from the imported document. The heading and action survive. The original FDX is unchanged; the loss is in the imported copy, and subsequent native saves cannot recover the omitted text.

Fixture: [fd13-dual-dialogue.fdx](AuditEvidence/fd13-dual-dialogue.fdx). Result: [fd13-dual-dialogue-result.json](AuditEvidence/fd13-dual-dialogue-result.json).

**First repair:** explicitly recognize this structure. Until a dual-dialogue model and renderer exist, block import with a precise explanation or offer a reviewed, clearly labeled sequential-text fallback that preserves every speech. Do not indiscriminately ingest all nested paragraphs: scene metadata and notes also contain paragraphs. Add actual Final Draft-generated fixtures and exact text-preservation assertions.

### F02 — P1: the main writing surface and exported pages use different typography

**Source-confirmed.** In unstyled legacy documents, `ContinuousScreenplayEditor.swift:71-78` uses 14-point Courier with four points of paragraph spacing and semibold headings/cues. `ScreenplayViewModel.swift:4533-4547` uses 12-point **system monospaced** text for default PDF output, with separate line spacing and layout rules. Thus the default PDF does not even necessarily use the Courier family advertised by the writing controls. Explicitly setting document typography removes part of the font difference, but does not unify the layout algorithms.

The legacy editor is a continuous text surface without the print engine's actual page containers; an explicit page-break element projects as an empty line through `writingText` at line 5931. The package editor has real page layout, but a narrower supported document profile. Neither successful PDF export nor a page-count label proves that the main writing surface shows the same line and page breaks.

**Repair:** one canonical style and layout contract consumed by editing, page count, preview, PDF, and print. Default to regular Courier-compatible 12 point; zoom changes display scale only. Keep deliberate authored style overrides. Verify exact line/page placement against reference fixtures before claiming WYSIWYG.

### F03 — P1: two document paths expose materially different writing products

**Source-confirmed.** File offers New Screenplay and New Package (`ScreenplayOSApp.swift:36-43`). Imports enter the legacy path. The package path has a stronger paginated writing surface and bounded history, but `PackageTextSession.swift:29-60` restricts companions, element fields, and eight element types. Production locks, revision metadata, notes, and richer project documents cannot simply become editable there. Package PDF explicitly has no title page (`PackageEditor.swift:376`).

**Repair:** converge the writing commands, styles, and layout first, with adapters that preserve the existing storage formats. Do not force migration or delete unsupported fields to obtain one editor. The end state is one predictable writing experience regardless of how a supported document was opened.

### F04 — P1: interchange does not support a professional round trip

**Source-confirmed.** There is FDX import but no FDX exporter in the source targets or File menu. DOCX imports text only. PDF extraction retains hard source-page breaks and extracted lines without reconstructing paragraphs, separating headers/footers, or recognizing title-page layout. `.fountain` is accepted as plain text rather than parsed as Fountain. Any textless PDF page blocks import, including an intentional blank page.

FDX import keeps supported inline emphasis and ordinary text, but does not reproduce element font/margin settings, revision/locking metadata, notes, alternates, or custom title layout. Some unsupported style names are warned about; that is not a complete loss inventory. Title text is flattened into title/subtitle fields, and AllCaps settings become changed text rather than a retained presentation property.

**Repair:** capability-aware import reports; word/structure preservation fixtures; safe FDX export tested by reopening in Final Draft. Treat DOCX/PDF as reviewed conversion paths, never lossless round trips. Add blank-page handling and role-correction preview before promising professional PDF reconstruction.

### F05 — P1: formatting is basic, not a reusable screenplay style system

**Source-confirmed and reference-checked.** Final Draft exposes per-element fonts, margins, paragraph spacing/alignment, Return behavior, pagination behavior, custom elements, and templates. ScreenplayOS persists document-wide family/size and four inline emphasis flags; most element layout values are constants. A4 is recognized in the typography value type but is rejected by the current editable package profile; the operative geometry is US Letter.

**Repair:** versioned style definitions, paper geometry, element behavior, and template application. Separate character-level marks from paragraph styles and display zoom. Add dual dialogue as actual structured content, not spaces or tabs. Preserve unknown/custom types safely.

### F06 — P1 for production use: revision marks are not track changes or full production revision support

**Source-confirmed.** The legacy path has per-element revision marks, labels/colors, reports, snapshots, and page-lock machinery. These are substantial partial capabilities. They do not provide a text-level insertion/deletion ledger with author attribution and accept/reject operations, nor a demonstrated Final Draft-compatible scene-number/omit/relock workflow. Package editing excludes these rich semantics.

**Repair:** distinguish Track Changes, revision sets, and production locks in both model and UI. Validate stable scene/page identifiers and A/B pages after insertion, deletion, undo, save/reopen, and export. Do not label the application production-ready on the strength of a Lock Pages button.

### F07 — P2: keyboard and long-document quality need comparative acceptance tests

Basic Return transitions, Tab cycling, character suggestions, find/replace, Unicode-aware editing, and undo tests exist. There is already a concrete engine discrepancy: legacy Return after Transition creates Scene Heading (`ScreenplayViewModel.swift:3501`), while the package Return handler creates Action for every type except Character/Parenthetical (`PackageParagraphTextView.swift:301`). SmartType's location/time/extension lists, configurable element transitions, automatic parenthesis insertion, and automatic same-speaker continueds are not established equivalents. Spellchecking may inherit some native behavior, but there is no verified application-level spelling/grammar workflow in this audit.

The historical 120-page benchmark reports roughly 98–100 ms median in Release with pauses (`Docs/typing-benchmark.md`); it is not a current result or a measurement of hardware key-to-screen latency. Package performance work does not establish legacy performance parity.

**Repair:** actual blank-page-to-script tasks and sustained 120/250-page writing sessions on the release build. Record median/tail latency, caret drift, scroll stability, IME behavior, undo granularity, and autosave pauses. Use reference-app comparison rather than calling any one timing threshold “industry standard.”

## Formatting reference captured from the installed app

These are defaults from the newly created Final Draft screenplay, not universal requirements for every screenplay template. Indents below are inches from the left edge of the page; the right value is an endpoint, not a margin width.

| Element | Left / right endpoint | Space before | Return creates | Default style |
| --- | --- | --- | --- | --- |
| Scene Heading | 1.50 / 7.50 | 24 pt | Action | Courier Final Draft 12, AllCaps |
| Action | 1.50 / 7.50 | 12 pt | Action | Courier Final Draft 12, regular |
| Character | 3.50 / 7.25 | 12 pt | Dialogue | Courier Final Draft 12, AllCaps |
| Parenthetical | 3.00 / 5.50 | 0 | Dialogue | 12 pt, first indent −0.10 inch |
| Dialogue | 2.50 / 6.00 | 0 | Action | Courier Final Draft 12, regular |
| Transition | 5.50 / 7.10 | 12 pt | Scene Heading | 12 pt, AllCaps, right aligned |

The reference uses US Letter, 72-point top/bottom margins, and document-level continuation/header settings. ScreenplayOS matches some horizontal indents but lacks the same complete style contract. A licensed font should not be copied into our distribution merely because it is installed on this machine; select a distributable Courier-compatible default and test its metrics.

## Feature coverage inventory

Status concerns ScreenplayOS at the reviewed revision. **Partial** means a bounded implementation exists, not parity. **Gap** means no equivalent was found in the inspected model, commands, and UI. **Unverified** requires further testing. Priority: **A** release safety, **B** core writing, **C** production/review, **D** later enhancement.

| Feature family / capability | Status | Evidence or next requirement | Priority |
| --- | --- | --- | --- |
| Core screenplay element roles | Partial | Eight shared writing roles; legacy also has page break | B |
| Automatic Return transitions | Partial | Fixed mappings; no element-behavior editor | B |
| Tab/Shift-Tab and element shortcuts | Partial | Cycles exist; compare reference context behavior | B |
| Character-name completion | Partial | Local cue suggestions; differs between editors | B |
| Location/time/intro/extension completion | Gap | No full SmartType list model/editor | B |
| Automatic parenthetical pairing | Unverified | Must test insertion/caret/undo explicitly | B |
| Automatic same-speaker CONT'D | Gap | Page continuations exist; separate same-scene rule missing | B |
| Dual-dialogue creation and editing | Gap | No paired-speech model or two-column renderer | B |
| Dual-dialogue FDX preservation | **Broken** | F01 actual omitted speeches | A |
| Font family and point size | Partial | Document-wide; default screen/PDF mismatch | B |
| Bold/italic/underline/strikeout | Present, bounded | Shared StyledText; current tests pass | B |
| Other underline styles/superscript/subscript/small caps | Gap | Not represented by supported inline style flags | D |
| Text color/highlight and character highlighting | Gap | Revision shading is not a general formatting feature | D |
| Per-element fonts and style presets | Gap | Hard-coded geometry; no stylesheet editor | B |
| Paragraph indents/alignment/line spacing | Partial | Engine constants, no full authored controls | B |
| Custom elements and pagination roles | Gap | Unknown imports map to General | B |
| Screenplay/teleplay/stageplay templates | Gap | No Final Draft-equivalent template application system | C |
| US Letter page geometry | Partial | Separate legacy and package engines | B |
| A4/custom page sizes and margins | Gap | Current writing/print paths fixed to Letter | B |
| Explicit page breaks | Partial | Legacy output supports; package profile excludes | B |
| Keep heading/cue with following text | Partial | Both print engines have grouping; reference corpus needed | B |
| Widow/orphan and speech splitting | Partial | Package two-line tests; compare all modes and legacy | B |
| Dialogue MORE and continued cue | Partial | Derived output, limited settings | B |
| Scene CONTINUED and continuation counters | Gap | No complete configurable production equivalent | C |
| Writing view equals exported pages | **Broken/partial** | F02; package has stronger layout than main editor | B |
| Title page | Partial | Legacy fields/fixed rectangles; absent package PDF title page | B |
| Headers/footers/page-number options | Partial | Basic page labels; no full configurable header/footer model | B |
| Watermarks/distribution personalization | Gap | No equivalent found | C |
| Print preview/PDF | Present, bounded | Both paths; no broad reference parity certification | B |
| Direct print/range/revised-page output | Partial/unverified | PDF workflow exists; complete production print UX unverified | C |
| Native continuous selection/copy/cut | Present, bounded | Native text views and tested cross-paragraph edits | B |
| Rich styled cross-app paste | Partial | Plain-text editing path; no full semantic clipboard exchange | B |
| Undo/redo and Unicode edits | Present, bounded | Current tests pass; workflows differ by editor | A |
| Find/replace | Present, bounded | Both paths; not FD-equivalent advanced search certification | B |
| Go to scene/page, navigator | Partial | Scene navigation present; compare page/bookmark navigation | B |
| Global semantic character rename | Gap | Find/replace is not identity-aware rename | C |
| Spelling/grammar/thesaurus | Unverified/gap | No verified equivalent command set | B |
| Speech/voices/dictation | Unverified/gap | Native OS affordances do not establish product support | D |
| Script notes/comments | Partial | Legacy notes/resolution; package anchors unsupported | C |
| Alternate dialogue/content | Gap | No authored alternatives model | C |
| Track changes with accept/reject | Gap | Revision marks are a different feature | C |
| Revision colors/labels/marks | Partial | Legacy element-level markers and reports | C |
| Revision sets and draft comparison | Partial/gap | Snapshots exist; no ScriptCompare equivalent | C |
| Scene numbering, locked numbers, omission | Partial/gap | Derived scene numbers; full production semantics unproven | C |
| Locked pages, A/B pages, relocking | Partial | Legacy machinery, not validated interoperability | C |
| Local save and external-change checks | Present, bounded | Atomic legacy writes; verified package generations | A |
| Autosave/recovery/backups | Partial | Legacy autosave; package recovery is not continuous normal save | A |
| Multi-document windows | Partial | Independent package windows; legacy main document differs | B |
| FDX import | Partial, unsafe for dual dialogue | F01 and F04 | A |
| FDX export/round trip | Gap | No exporter | B |
| DOCX import | Partial | Text-only, reviewed extraction | B |
| PDF import | Partial | No layout reconstruction/OCR; blank pages block | B |
| Plain-text import | Partial | UTF-8/BOM UTF-16; heuristic roles | B |
| Fountain interchange | Gap | Extension accepted as text; no syntax parser/exporter | C |
| RTF/DOCX/text screenplay export | Gap | PDF/report exports are not editable screenplay interchange | C |
| Outline/cards/scene reordering | Partial | Existing source-linked Outline; not Beat Board parity | C |
| Beat Board/multi-lane outlines/structure lines | Partial/gap | Different existing planning model | D |
| Bookmarks/macros/labels/images | Gap | No equivalent writing command set found | D |
| Format Assistant/reformatting | Partial | Role controls/import heuristics; no broad format lint/repair | B |
| Character/location/scene/statistics reports | Partial | Existing reports need parity and output review | C |
| Production tagging/cast lists | Partial/gap | Context records exist; no full FD tagging/cast-list workflow | C |
| Real-time collaboration | Gap, deliberately deferred | Must not compromise offline free-core writing | D |
| Focus/dark page/zoom | Present, bounded | Existing controls; logical page geometry must remain fixed | B |
| Split script views/ruler/invisibles | Gap/partial | Multi-workspace panes are not split writing views | D |
| Goals/sprints/writing statistics | Gap | Defer until core writing is dependable | D |
| Accessibility, IME, RTL, unusual Unicode | Unverified broadly | Existing Unicode tests cover only a subset | B |

## Ordered implementation plan and acceptance gates

### Gate 1: preserve every word

1. Repair or safely block dual-dialogue imports and add the native-generated regression fixture.
2. Inventory FDX containers: ordinary body, dual dialogue, notes, alternate content, title pages, revisions, and custom elements. Define what is preserved, converted, previewed, or rejected.
3. Require explicit reports for unsupported semantics. Missing text must never be hidden behind a generic formatting notice.
4. Exercise import → save → reopen → undo/redo with exact text/role assertions and source checksums. Include empty paragraphs, Unicode, malformed XML, nested metadata, and mixed styles.

**Exit:** no unnoticed text omission on the declared supported corpus. All unsupported cases stop safely or require review of an explicit fallback. Existing user documents remain unchanged.

### Gate 2: make the page trustworthy

1. Establish shared Courier-compatible 12-point defaults and authored element styles.
2. Make one layout service own line wrapping, page breaks, continuation labels, page numbers, preview, and PDF.
3. Use adapters to connect both file representations without forced migration.
4. Add golden fixtures for every core element, long dialogue, interrupted speeches, dual dialogue, parentheticals, blank lines, explicit breaks, long title pages, accents/emoji, and font substitution.

**Exit:** the edit surface and exported PDF agree in line/page breaks at every zoom. Reference comparisons record any intentional differences. Page counts remain stable after save/reopen and display-only changes.

### Gate 3: complete the everyday writing loop

Keyboard-first entry, SmartType-style assistance, safe paste, find/replace, character rename, spelling, title page/header controls, and FDX export/reopen in Final Draft. Compare blank-page → several scenes → dialogue revision → export without requiring production tools or frequent element-menu visits.

**Exit:** representative writing tasks work correctly in both document paths, including failures and cancellation. Sustained long-document testing shows acceptable latency and stable caret/selection. Imported supported formatting is retained through the loop.

### Gate 4: production and review

Track changes, revision sets, scene numbering/omission, locked pages, notes/alternates, and production PDF output, backed by real Final Draft fixtures and fault/recovery checks. Only then resume discretionary timeline expansion.

This is an order of work, not permission to market Final Draft parity or a commitment to reproduce every peripheral feature before useful writing releases.

## Official reference sources

Accessed 2026-10-01. Native menu observations above supply additional evidence beyond these pages.

- [Final Draft feature overview](https://www.finaldraft.com/products/features/): feature-family scope, planning, writing, reporting, revision and collaboration features.
- [Element settings](https://kb.finaldraft.com/hc/en-us/articles/27647938211604-How-do-I-modify-element-behavior-change-element-fonts-and-margins-or-create-new-custom-elements): per-element styles, behavior and templates.
- [Script elements](https://kb.finaldraft.com/hc/en-us/articles/27646947570196-What-are-script-elements): element semantics, cast lists and automatic continueds.
- [Dual dialogue](https://kb.finaldraft.com/hc/en-us/articles/15575256060564-How-can-I-make-my-characters-and-dialogue-side-by-side-on-the-page): side-by-side speeches.
- [Mores and continueds](https://kb.finaldraft.com/hc/en-us/articles/27747514444180-How-do-I-modify-or-remove-Mores-and-Continueds-CONT-Ds): separate dialogue, character and scene continuation controls.
- [Script panel views](https://kb.finaldraft.com/hc/en-us/articles/27941900148884-How-does-the-Script-panel-work-Normal-View-Page-View-Speed-View): page/normal/speed presentation.
- [PDF import](https://kb.finaldraft.com/hc/en-us/articles/15573804499604-Can-Final-Draft-import-a-PDF): documented text-PDF title/script reconstruction; not a guarantee for every PDF.
- [Track changes](https://kb.finaldraft.com/hc/en-us/articles/15573791756180-Can-Final-Draft-track-changes-when-more-than-one-person-works-on-a-script): insertion/deletion review and accept/reject.
- [Collaboration](https://kb.finaldraft.com/hc/en-us/articles/27781252742804-How-do-I-use-the-Collaboration-tool): shared script and Beat Board sessions.
- [RTF export](https://kb.finaldraft.com/hc/en-us/articles/15575247351956-How-can-I-keep-script-text-formatted-in-the-body-of-an-e-mail-message): editable external export and its pagination limitation.
- [Templates](https://kb.finaldraft.com/hc/en-us/articles/15575230572692-What-are-templates): reusable document-level configuration.
- [Manual index](https://www.finaldraft.com/support/manuals-and-software/fd13/): source location; full PDF retrieval was unsuccessful.
