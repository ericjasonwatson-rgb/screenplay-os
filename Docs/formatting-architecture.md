# Formatting architecture: foundation

Status: domain foundation and package inline-formatting pipeline implemented. Document typography transactions and initial Format controls are enabled.

## Ownership

Paragraph type remains structural: scene heading, action, character and dialogue determine screenplay layout. Inline emphasis is separate paragraph-local data: exact Unicode text plus ordered `runs` with scalar start/length and optional Boolean bold, italic, underline and strikethrough keys. DocumentTypography describes document-level paper, font family and point size. Zoom, dark paper, panel visibility, cursor and insertion style remain transient presentation state.

The default typography projection is Courier, 12 points, US Letter, following the user's current Courier direction. The older draft example uses Courier Prime; no existing file is rewritten to either default. The projection recognizes US Letter/A4 names and positive finite font sizes up to 200 points as an initial implementation bound. Recognition does not establish working A4 pagination. Actual installed-font resolution belongs in the native rendering adapter, which must report substitution; it must not rewrite the requested font name silently.

## Implemented

StyledText validates run bounds without integer overflow. It preserves ordered runs on reading; resolvedRuns applies later-run overrides per explicitly supplied key, including false. Command results use nonoverlapping canonical runs. Unknown keys and invalid ranges/styles reject the typed projection rather than silently dropping information. The preserving package reader must retain source bytes and present its existing read-only fallback on rejection. JSONDecoder alone is not a replacement for duplicate-key detection or byte-preserving package parsing.

Interactive range conversion validates both UTF-16 and Unicode-scalar offsets and requires grapheme boundaries, including emoji sequences and combining marks. Stored ranges may follow the draft's scalar semantics; interactive commands cannot split a grapheme. Formatting a caret-only selection is a no-op; future typing controls hold insertion style separately. Replacement receives insertion style explicitly. Formatting patches, clear emphasis, replacement, split and append maintain the text/style relationship. Exact scalar equality distinguishes canonically equivalent Unicode spellings.

StyledTextHistory is a paragraph command harness backed by the existing PreservedJSONSession byte-history kernel. It validates expected revisions, commits candidate state only after successful commands, and restores text/runs together. It is not a second live UI undo stack. Integration must submit the entire text/run/paragraph-identity change to PackageTextSession's existing document transaction, including multi-paragraph edits and find/replace.

## Package integration

The conservative package editor accepts recognized inline runs and an optional settings.json containing only formatting. Unsupported companions, unknown keys, malformed runs, duplicate JSON keys and unsupported paper sizes still reject editing. US Letter is the only enabled paper size. Existing files are not migrated.

PackageTextSession submits text and run changes together to its existing document history. Replacement, find/replace, split and cross-paragraph edits preserve surviving emphasis and paragraph identity; undo restores exact prior screenplay bytes. New text inherits the resolved style immediately to its left, or the first scalar's style at paragraph start. Empty paragraphs use plain text unless an explicit caret style is active. Caret formatting is transient per editor: it creates no document edit until typing, survives consecutive typing and paragraph splits, and resets on cursor movement or undo/redo.

Font family and point size belong to document settings; absence uses Courier 12. The same native font/style adapter feeds attributed editor text and measured PDF layout. Editor layout uses document point sizes directly. Shared US Letter geometry fixes the page at 612 points, with a 432-point text area, 108-point left margin, 72-point right/top margins, and the same paragraph indents and spacing as PDF layout. Narrow windows scroll horizontally without reflowing the document. Missing font names show a substitution notice and use Courier without changing saved settings. Font variant availability and script-specific glyph fallback still depend on AppKit. Semantic paragraph types control layout; headings no longer receive implicit bold in the package editor.

Save snapshots, staged writes, conflict checks, retained generations and recovery include settings.json. Untouched settings bytes remain exact. Inline formatting modifies screenplay.json. Typography changes modify settings.json; the history kernel stores its optional exact bytes alongside screenplay bytes, counts both against the history budget, and restores absence on undo. Both participate in dirty-state, conflict checks and recovery. The Format menu exposes document font/size and emphasis toggles for selections or subsequent typing. Native Command-B, Command-I and Command-U toggle bold, italic and underline. Mixed selections toggle to uniformly enabled; uniformly enabled selections toggle off. Multi-paragraph emphasis is a single transaction. Clear Emphasis removes inline emphasis without changing document typography.

## Remaining formatting work

1. The writing surface remains continuous: page breaks, continuation cues and page numbers remain in Print Preview. Shared geometry aligns authored line wrapping but does not make the editor a paginated preview.
2. Consider a separate indeterminate menu indicator for mixed selections. The current unchecked state covers both mixed and uniformly disabled selections.
3. Test unavailable font variants and broader typography/pagination combinations before claiming arbitrary-font fidelity. A4 remains disabled.
4. FDX/Fountain interchange requires explicit preservation/loss tests before rich round-trip claims. Legacy JSON editing has not been migrated to this package pipeline.

This implementation is not full draft-format conformance.

## Verification

Domain coverage includes Unicode scalar spelling, grapheme boundaries, overlapping runs and explicit false, invalid ranges, and atomic history. Package integration coverage adds styled replacement, find/replace, split/join, exact undo, save/reopen, Save As, retained generations, recovery, external settings conflicts, interrupted settings writes, shared native/PDF rendering, fallback-font disclosure, and unsupported-content rejection.

### Live verification

Verified in build 4b57d9c using only the synthetic Formatting Integration.screenplay package: white page and four emphasis styles, Command-B toggle on/off, Command-I and Command-U, Clear Emphasis through the menu, bold subsequent typing, Undo, changing size from 16 to 24 pt, styled Print Preview, Save and reopen. Reopened menu retained Courier 24 pt and the document reported no unsaved changes. Font-family switching and mixed-state menu indicators were not exercised live. The previously stuck path sheet was dismissed using Command-period; the application then restarted normally.

### Shared layout verification

Native TextKit line ranges are compared with the final PDF layout across all supported paragraph types, inline bold/italic, Courier and Helvetica at 12/16/24 points, and wide/narrow windows. Page width is held independently of the viewport. These checks cover line wrapping; editor pagination and continuation markers are not implemented.

Live check: the synthetic Courier 24 pt formatting fixture now wraps into the same three action lines in the editor and Print Preview, with matching inline emphasis. Source text and saved typography were unchanged by the layout update. Full suite: 154 Swift tests, 37 Python tests and 14 self-tests passed.
