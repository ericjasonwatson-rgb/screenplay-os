# Build 26: retain printed pagination in the writing editor

The 106-page stress script exposed a print-splitting error around a hyphenated word. The old paginator measured successively shortened text and then backed up to the last whitespace. In one paragraph it split at character 50, while native wrapping put the next line at character 59. The editor correctly rejected this incompatible page plan and fell back to continuous view.

The paginator now measures the complete remaining paragraph in TextKit and splits only at an actual line boundary that fits the available height. This preserves whitespace, attributed formatting, and canonical source text. PDF, preview, and the writing page plan share the resulting fragments. The editor's safety check remains intact; this is not a claim that every possible imported or locked layout can be represented as editable pages.

A regression expands the existing screenplay fixture to 2,112 elements and checks that the editor accepts the page plan, every native line matches its printed vertical position, and every page-start caret resolves to the corresponding page. These checks run before editing, after inserting text in the middle, and after Undo; the original elements must be restored. Existing Unicode, styling, page-lock, continuation, navigation, persistence, and editor tests also remain required.

The same 20-insertion release benchmark, with navigator and context visible, measured a warm median of 56.2 ms and first insertion of 160.2 ms. Build 25 measured 55.7 ms and 162.0 ms respectively. This run shows no material regression while restoring the stress script's editable page layout; timing is machine/run-specific.
