# Writing workflow and export audit

Date: October 3, 2026. Scope: native first-launch and writing workflow regression coverage, source review of menu/save/export entry points, and visual inspection of a synthetic four-page PDF. This is not a full manual usability study or a claim of Final Draft parity.

## Fixed export defects

The title-page editor presents contact information followed by the draft date, left-aligned in Courier. The export renderer used date followed by contact, centered in a different monospaced font at 10 points. Export now follows the editor's order, alignment and 12-point Courier treatment. The title editor now renders the actual export page; see the preview follow-up below.

The old footer used a fixed 90-point rectangle without checking its content height. Long contact blocks could be omitted from the PDF without an error. Export now measures both title/credits and footer, expands the footer where space permits, and rejects overflow or overlap with a clear instruction to shorten title-page text. It neither edits authored text nor replaces an existing PDF when rendering fails. Extremely long title/credit blocks are also rejected rather than clipped.

## Verification

- First launch: blank unsaved screenplay, Script mode, white paper, no demo content or production panes.
- Recent work: surviving recent file reopens; missing paths do not block it; an unreadable recent file remains untouched and produces an explanation.
- New from another mode: prior work is preserved and the app returns to the writing workspace.
- Native writing: existing integration tests cover FDX import, typing, formatting, selection, Undo/Redo, pane changes, Save, close and reopen.
- Export: added a twelve-line contact block fixture, verified its final line and draft date survive PDF extraction, checked left alignment by PDF text bounds, and tested oversized contacts/credits. Failed export preserves existing output bytes and the authored document.
- Visual review: rendered and inspected every page of the four-page synthetic PDF at 1,000-pixel resolution. Checked title/author separation, complete footer, dialogue continuation cues, page labels and explicit page break. No clipping or overlap was observed in this fixture.
- Full Release result: 212 Swift tests, 37 Python checks and 14 self-tests, totaling 263 checks. Debug and a fresh manually operated app session were not repeated.

Evidence is in workspace `work/writing-audit-2026-10-03/`: release test log, synthetic PDF and four rendered PNGs. No user screenplay was modified.

## Remaining issues and next boundaries

1. Creation-menu follow-up: New Screenplay is now the first creation command. The limited editor is under Experimental Features as New Writing-Only Screenplay, with help explaining unavailable modes and title-page editing. Command-N and Shift-Command-N keep their existing actions. No format migration or document behavior changed. Release compilation verifies the menu change; a live menu/accessibility review remains outstanding.
2. Title-preview follow-up: the approximate SwiftUI page has been replaced with the actual title-only export PDF. The same renderer supplies both preview and complete export.
3. Automated workflow success does not establish discoverability. A real first-time writing session remains useful before distribution.
4. Typing still exceeds the under-50-ms target, particularly with both content panels open. This export change makes no responsiveness claim.
5. Developer ID distribution and notarization remain pending. The existing 0.1.2 ZIP does not contain these new export fixes until another package is built.

The StoryKit proposal remains pending review. No cloud service or architecture migration is introduced.


## Exact title preview follow-up

The title editor now renders the title-only PDF after a 150 ms pause in editing. It does not paginate the full script. New field values cancel pending renders; overflow replaces the preview with an explanation, and correcting the text restores the preview. The preview is a read-only page drawing; fields remain the editing surface.

An initial interactive PDFView implementation triggered a PDFKit tile-release crash during testing. It was replaced with direct drawing of the generated PDF page in a native view, without PDFView's asynchronous tiled-view lifecycle. The existing full Print Preview is not changed by this work.

Tests compare title-only and complete-export page text and rendered images, confirm a single preview page, and exercise rapid title replacement, overflow, and recovery in a native hosted editor. Full Release validation passed 213 Swift tests, 37 Python checks and 14 self-tests (264 checks). A follow-up targeted native test uses the app's dark appearance for capture. Evidence: workspace `work/title-preview-2026-10-03/`. This change is not yet included in the distributed local beta ZIP.
