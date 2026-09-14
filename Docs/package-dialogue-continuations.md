# Dialogue continuation markers in package print output

The minimal-package print layout now adds `(MORE)` at a page boundary inside a cued dialogue block and repeats the character cue with `(CONT’D)` at the top of the next page. Both are derived PDF presentation, shared by Print Preview and Export PDF. They are never inserted into screenplay.json, recovery, or Undo history.

A dialogue block begins at a nonblank character cue and includes consecutive dialogue and parenthetical paragraphs. Action, scene headings, transitions, and other types end the block. Un-cued dialogue and blank cues print without invented speaker names. Existing trailing `(CONT'D)` or `(CONT’D)` on the cue is not doubled in the repeated header. Authored cue wording, case, and extensions remain unchanged.

The paginator measures the repeated cue, reserves its height before laying out the next page, and reserves 24 points for MORE before finalizing a continuing page. It rechecks cue/parenthetical grouping after that reservation. First pages receive no repeated cue; final dialogue pages receive no MORE. Longer character cues wrap within the header area. Pathological repeated headers requiring 500 points or more fail the preview safely rather than overlap the body or prevent pagination progress.

The existing rules keep end-of-page headings, character cues, and parentheticals with following text when the group fits. Oversized authored blocks must still make progress. This does not implement production locks, dialogue widow/orphan tuning, scene CONTINUED labels, or all screenplay-format conventions; the supported minimal editing profile is unchanged.

The automated seven-page dialogue fixture verifies paired markers on every continuing page, the correct final-page behavior, contiguous authored character coverage, and exactly one occurrence of each of 1,400 numbered test words in extracted PDF text. Additional tests cover short dialogue, multiple speakers, parenthetical grouping, blank/missing cues, interruption by action, existing continuation suffixes, preview cleanliness, and byte-identical screenplay content after a separate-copy save. First, second, and final rendered pages were visually inspected for marker/body separation. The full suite passed 114 Swift tests, 37 Python tests, and 14 self-tests.

The final live app check is pending: macOS returned repeated AppleEvent reopening timeouts after the build was packaged. This does not change the completed PDF rendering/extraction checks or automated preview/save tests; it prevents claiming a new on-screen verification for this change.
