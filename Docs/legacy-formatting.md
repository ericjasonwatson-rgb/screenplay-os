# Formatting in legacy monolithic documents

This is an additive compatibility extension for the older `.open-screenplay.json` editor, not package-format conformance or a package migration. The package and legacy editors now use `WritingFormattingBar` and the same `StyledText` / `DocumentTypography` primitives. Their editing and persistence adapters remain separate.

## Storage

Unformatted 1.0 documents retain their existing fields and rendering behavior. Applying persisted typography or emphasis changes the legacy declaration to `format_version: "1.1"`. An optional root `typography` object stores `paper`, `font_family`, and `font_size`. Optional element `runs` store Unicode-scalar ranges with bold, italic, underline and strikethrough flags. Text remains the sole authored text; style records contain no duplicate screenplay text. Empty runs are omitted after editing.

`Specs/legacy-screenplay-1.1.schema.json` describes the extension. The application validates supported legacy version declarations, typography and run bounds on decode. Unsupported styles, versions, or paper settings fail to open for editing rather than being silently stripped. The source file remains intact. Legacy 1.1 supports US Letter; title-page styling remains controlled by the existing title-page template.

This build reads both legacy 1.0 and 1.1. Older builds do not preserve these new formatting fields and should not edit 1.1 files. The experimental legacy-to-package converter still blocks 1.1: its mapping and schema must be extended before converting styled legacy files. Neither draft-package conformance nor lossless FDX style import is claimed.

## Editing and history

Typography changes apply to screenplay text throughout the document. Emphasis applies to selected text, or to subsequent typing when the selection is empty. The insertion override is transient; caret movement, document changes and undo/redo clear it. Commands use existing whole-document undo and local persistence, retaining creative identities, notes, production data and relationships.

Native edits supply exact UTF-16 ranges, converted to Unicode-scalar/grapheme-safe ranges before changing styles. This avoids ambiguous remapping in repeated text. Paragraph splits, joins and cross-paragraph replacements preserve the retained spans. Whole-text normalization maps unaffected prefixes/suffixes; uppercase expansions retain the originating character's style. Replace All operates on individual matches so styles between matches survive. Duplicated scenes get new identities while retaining their source text styles.

Both interfaces use the same font, size and emphasis controls. The toolbar adapts to two rows in narrow panes. Font substitution is disclosed. Zoom remains independent of persisted typography.

## Rendering

The native legacy view applies saved runs through the shared font adapter. Script PDF measurement and drawing use the same attributed text for each printed fragment. Explicit page breaks and production locks remain supported; locked fragments slice styles using their exact character boundaries. Generated continuation labels remain derived output. Both measurement and page-layout caches include typography, preventing stale-font PDFs after a font-only edit.

## Verification

Regression coverage includes old-file defaults, complete authored-state save/reopen and undo/redo, exact insertion in repeated text, Unicode input, explicit and cross-paragraph splits/joins, scene duplication, Replace All, native font/underline attributes and selection, uppercase expansion, malformed-run rejection, and styled PDF fragments with production locks. PDF checks warm the old-font cache before changing only typography. Save timestamps retain their established update-on-save behavior and are excluded from authored-state equality checks.

The package recovery scheduling check now awaits the actual debounce task under a one-minute test limit. It does not force a recovery write or use a five-second polling deadline that unrelated native-layout tests can consume. The production debounce interval is unchanged.

Final verification: 165 Swift tests, 37 Python checks, and 14 executable self-tests passed (216 total). The release app was rebuilt, and a synthetic legacy document was reopened with Helvetica 16 and bold/italic/underline intact. The script PDF preview was visually checked against that saved formatting.
