# Formatting architecture: foundation

Status: implemented domain foundation; package integration and formatting controls are not enabled.

## Ownership

Paragraph type remains structural: scene heading, action, character and dialogue determine screenplay layout. Inline emphasis is separate paragraph-local data: exact Unicode text plus ordered `runs` with scalar start/length and optional Boolean bold, italic, underline and strikethrough keys. DocumentTypography describes document-level paper, font family and point size. Zoom, dark paper, panel visibility, cursor and insertion style remain transient presentation state.

The default typography projection is Courier, 12 points, US Letter, following the user's current Courier direction. The older draft example uses Courier Prime; no existing file is rewritten to either default. The projection recognizes US Letter/A4 names and positive finite font sizes up to 200 points as an initial implementation bound. Recognition does not establish working A4 pagination. Actual installed-font resolution belongs in the native rendering adapter, which must report substitution; it must not rewrite the requested font name silently.

## Implemented

StyledText validates run bounds without integer overflow. It preserves ordered runs on reading; resolvedRuns applies later-run overrides per explicitly supplied key, including false. Command results use nonoverlapping canonical runs. Unknown keys and invalid ranges/styles reject the typed projection rather than silently dropping information. The preserving package reader must retain source bytes and present its existing read-only fallback on rejection. JSONDecoder alone is not a replacement for duplicate-key detection or byte-preserving package parsing.

Interactive range conversion validates both UTF-16 and Unicode-scalar offsets and requires grapheme boundaries, including emoji sequences and combining marks. Stored ranges may follow the draft's scalar semantics; interactive commands cannot split a grapheme. Formatting a caret-only selection is a no-op; future typing controls hold insertion style separately. Replacement receives insertion style explicitly. Formatting patches, clear emphasis, replacement, split and append maintain the text/style relationship. Exact scalar equality distinguishes canonically equivalent Unicode spellings.

StyledTextHistory is a paragraph command harness backed by the existing PreservedJSONSession byte-history kernel. It validates expected revisions, commits candidate state only after successful commands, and restores text/runs together. It is not a second live UI undo stack. Integration must submit the entire text/run/paragraph-identity change to PackageTextSession's existing document transaction, including multi-paragraph edits and find/replace.

## Gates before controls

1. Extend the preserving package projection for recognized runs and settings.json, retaining all original bytes outside the explicit change. Unknown semantics still block editing.
2. Update every creative command: replacement, paste, cut, split, join, deletion, paragraph type changes, find/replace and cross-paragraph edits. Preserve UUIDs and use one document-wide undo transaction. No string-only command may silently drop runs.
3. Feed the same resolved inline styles and document typography into native attributed text and PDF layout. Resolve fonts at the adapter boundary, disclose substitution, distinguish display zoom from document size, and remeasure pagination.
4. Expand save snapshots, staging, conflict checks, retained generations and recovery to include settings and runs. Test Save, Save As, repeated save, restart, interruption and external changes with styled fixtures.
5. Only then expose a Format control and shortcuts. FDX/Fountain interchange needs explicit preservation/loss tests before rich round-trip claims.

No package support guard was relaxed in this change. Current application saves, migration behavior and export remain unchanged. This foundation is not full rich-text editing, completed draft-format conformance, or a finished typography pipeline.

## Verification

Domain tests cover overlap resolution, explicit false, exact Unicode serialization, grapheme/UTF-16 conversion, overflow rejection, run movement across replacement, split/join, clear emphasis, stale and failed transactions, undo/redo, malformed and unknown styles, document typography serialization, and canonically equivalent text preservation. The full suite passed 142 Swift tests, 37 Python tests and 14 self-tests: 193 checks. No UI changed, so no new native interaction test was required for this isolated domain foundation.
