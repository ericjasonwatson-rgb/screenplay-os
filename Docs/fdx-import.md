# FDX import verification

The importer reads ordinary screenplay paragraphs from `FinalDraft/Content/Paragraph`
and direct text children. Reviewed dual-dialogue conversion also reads the exact
`FinalDraft/Content/Paragraph/DualDialogue/Paragraph` path. Title-page paragraphs are kept separately; text in
headers, scene metadata, and nested metadata paragraphs cannot enter the script.
Blank screenplay paragraphs, whitespace, source paragraph IDs, and explicit
page breaks are retained. `StartsNewPage="Yes"` produces a native page break.

Inline bold, italic, underline, and strikeout become persisted native style runs,
using Unicode scalar offsets. Styled imports use legacy format version 1.1.
Declared element-level and text-level AllCaps are applied to the imported text;
this intentionally materializes Final Draft's display casing. Other text is
unchanged. The original FDX is never written by the importer.

Arbitrary title-page text is retained in title/subtitle rather than guessing its
author/contact semantics. The import notice asks the user to review those fields.
Unsupported paragraph types and inline styles produce warnings. Non-FinalDraft
XML, non-Script documents, missing script Content, and malformed XML are rejected.

This is not lossless Final Draft interchange. Custom fonts, inherited emphasis
from element settings, paragraph layout, dual dialogue, production metadata,
revision history, and custom title-page positioning are not fully supported.
The app reports that native layout is used; exact Final Draft pagination is not
claimed. Do not replace an original FDX with an imported native copy as an archive.

September 30 verification against the user's supplied Chickamauga FDX:
all 173 direct script paragraphs matched source order, IDs, and text after its
declared AllCaps settings; all four inline italic runs were retained. The six
nonempty title-page lines no longer appear in the screenplay body. Six blank
script paragraphs previously dropped are now retained. The source remains outside
the repository; regression fixtures use synthetic text.


## Dual-dialogue safety repair — October 1, 2026

The audit's Final Draft 13.4-generated fixture is now a regression test. Default
library/CLI import refuses dual dialogue with a specific review-required error.
The Mac app previews a sequential-text conversion and requires Import Sequential
Copy; Return defaults to Cancel. Cancelling does not replace the current script.
The source bytes are read once for parsing and review, and the original FDX is
never an output destination. Acceptance retains save-before-replace protection.

The supported wrapper contains two character-led speeches with dialogue and
optional parentheticals. Child IDs, whitespace, supported inline emphasis, and
page-break flags are retained; wrapper page breaks move to the first speech.
Spellcheck metadata is excluded. Mixed wrapper text, unsupported roles, nested
or misplaced dual containers, and incomplete speech pairs fail closed. Unknown
shapes must not silently become an empty paragraph.

The converted native document contains ordinary sequential paragraphs. It does
not preserve dual-dialogue grouping or simultaneous delivery. Full dual-dialogue
editing, rendering, and FDX export remain outstanding; keep the original FDX.

Verification: 177 Swift tests, 37 Python checks, and 14 executable self-tests
pass (228 total). Tests cover the real generated fixture, multiple blocks,
Unicode emphasis, source IDs, page breaks, malformed shapes, importer reuse,
review cancellation/acceptance, separate native save, reopen, and original-byte
preservation. The CLI now reports expected import errors with exit status 1
instead of an uncaught-error crash.

Live verification displayed both speeches in the review and confirmed Return
cancellation retained the original blank draft. After clicking acceptance, the
computer-use service timed out repeatedly on the isolated test application.
The accepted editor state was not verified live; the automated acceptance and
save/reopen cases pass. This limitation remains open and is not counted as a
successful live import.
