# FDX import verification

The importer reads screenplay paragraphs only from `FinalDraft/Content/Paragraph`
and direct text children. Title-page paragraphs are kept separately; text in
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
