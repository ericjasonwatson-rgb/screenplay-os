# Independent edit order and text document imports

## Authored edit order

The first Move Earlier/Later in Edit command upgrades the legacy document to 1.2.
The existing editorial sequence/beat IDs, arrays, and `order` values are retained;
no screenplay paragraphs move. Version 1.2 makes beat order authoritative across
save/reopen and subsequent screenplay reorders. New screenplay scenes append to
the edit. Undo/Redo includes the version declaration and edit order together.
Typography commands must never downgrade 1.2 to 1.1.

Unedited 1.0/1.1 guides retain their existing source-derived behavior until an
explicit edit-order command. The package editor has no filmmaking edit surface;
this change does not implement the draft film/edit.json envelope or migrate it.
Use 1.2 documents in this build or later. The immediately preceding builds reject
1.2; much older readers may lack version guards and must not edit these files.

The clip time ruler uses durations to set exact horizontal widths. Whole-edit
playback and scrubbing traverse clips in edit order and update scene/board
selection. Stored shot placeholders retain the legacy four-second default, but as of October 8 they contribute no derived playback/export time;
untimed scenes have no invented runtime and remain in the scene strip. This is
board/placeholder playback, not a video player. Clip trimming and drag reordering
are not implemented. Clip order/timing still derive from boards and shots.
Deleting a source scene still prunes its derived beat; independent occurrence
retention and explicit orphan repair are further architecture work.

## DOCX, PDF, and plain text

Open now routes DOCX, text-based PDF, UTF-8 text, and BOM-marked UTF-16 text to a
local review dialog. Keep Paragraphs assigns neutral roles; Detect Structure uses
conservative line heuristics. Neither option rewrites the extracted words or
trims authored whitespace. Line endings become native paragraph boundaries.
Detection is not a Fountain parser and may need manual correction.

DOCX uses the macOS attributed-string reader but imports text only. Fonts,
emphasis, images, comments, and custom layout are not carried over. The preview
asks users to check tables and text boxes. PDFKit extracts selectable text in its
reported reading order, keeping page boundaries as explicit breaks. No OCR,
dehyphenation, header removal, or guessed reading-order repair is performed.
Locked PDFs and PDFs with any textless page are blocked rather than silently
importing a partial script. A genuinely blank page also requires review outside
this initial importer.

Import is limited to 20 MB, 1,000 PDF pages, and 500,000 extracted characters.
The dialog can be cancelled before replacing the current document. Acceptance
uses existing save-before-replace protection; the source is never an output
destination. Subsequent saves create a native document separately.

## Verification

The regression suite passes 173 Swift tests, 37 Python checks, and 14 importer
self-tests. Synthetic fixtures cover saved edit order, Undo/Redo, typography
version preservation, cross-scene playback, source preservation, and real DOCX
and PDF extraction. Live app checks verified the import preview, detected text
structure, proportional 3/6-second clips, scene navigation, context-menu
reordering, and playback stopping at nine seconds in the reordered second scene.
