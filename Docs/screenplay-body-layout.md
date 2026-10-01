# Shared legacy screenplay body layout

The continuous native editor and legacy PDF renderer now obtain element geometry
from `ScreenplayBodyLayout`. Existing print geometry remains the reference for
this repair. The shared values include widths, indents, alignment, spacing before
and after paragraphs, and two-point line spacing. Fonts continue to resolve from
document typography, defaulting to regular Courier 12.

The editor previously gave transitions 163 points of width while PDF used 115,
added four points after every paragraph, and gave General paragraphs no leading
space while PDF used 12. Those differences are removed. Zoom scales the editor's
metrics only. Page count and printed text remain independent of zoom.
The native scroll view also refreshes page geometry after SwiftUI resizes the
page well, and lowers the previous minimum width before zooming out. This fixes
text remaining shifted sideways after returning from a larger zoom.

## Verification

The native-host regression compares wrapped text lines for all eight text element
types against the attributed fragments actually supplied to PDF drawing, at 100%
and 200%. It compares glyph baselines (line rectangles include paragraph-leading
space), allows up to half a point of normalized TextKit rounding at 200%, and
checks indents and paragraph spacing, then returns to 100% and checks the editor
width and centered text inset. Blank elements and explicit page-break
records remain in the source. Viewing and zooming leave saved source bytes and
in-memory document values unchanged. The existing suite also covers continuation
markers, explicit breaks, production locks, text/style persistence, selection,
typing, and undo.

## Limits and next step

This is shared body geometry, not editable page parity. The continuous editor
still has one unbounded text container. PDF separately places pages, splits long
paragraphs, keeps cue/dialogue groups together, and adds continuation markers.
Its text normalization and blank-paragraph handling also need reconciliation.
The `.screenplay` package editor has a separate TextKit pagination plan; this
change does not merge those engines or migrate documents.

`printedLayout` now wraps the existing PDF pages in a `ScriptPrintProjection`.
Every authored fragment carries an element-local and document-global UTF-16 source
range. The mapping handles print-only whitespace trimming and uppercase expansion
(such as ß to SS), and never searches another element for matching text. Synthetic
continuation markers have no editable source span. Blank paragraphs and explicit
breaks remain in the projection's complete source-entry list even when current
print policy omits them. Mismatched or missing fragments are reported through
`unmappedElementIDs`; future editable consumers must reject incomplete mappings.
The projection is cached with the document, typography, and production lock and
is never persisted. Production-locked fragments map against the original source,
not the temporary normalized stream. Tests cover Unicode, repeated text, trimming,
blank/break retention, synthetic markers, locked reopen, and fail-closed mapping.

This adds source identity to the current print plan; it does not yet move either
renderer onto a unified page-placement engine. The next step is to use one plan
for page placement and PDF before exposing editable page boundaries.
Keep authored blank paragraphs, Unicode selections, explicit breaks, undo, and
production-lock identity in acceptance tests. Never inject display-only markers
or page gaps into the saved screenplay to simulate pagination.

## Printed-page navigation

The bottom page status is now a menu of PDF page labels, excluding the title page.
Choosing a page restores the editor caret to its first authored fragment, skipping
synthetic continuation markers. The status follows the start of the current
selection. At an exact fragment boundary, the caret belongs to the following
fragment. Leading/trailing whitespace follows its own paragraph; unprinted blank
paragraphs and breaks show only the total page count. Omitted pages without text
cannot be navigation targets. Incomplete source mappings disable navigation.

Navigation changes only selection and its restoration token, not screenplay text,
undo history, or saved bytes. Regression checks include a long Unicode dialogue
spanning pages, exact boundaries, invalid targets, and unchanged saved content.
The editor remains continuous: this menu does not render editable page gaps.
