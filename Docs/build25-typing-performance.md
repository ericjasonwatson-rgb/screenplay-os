# Build 25: continuous-view typing performance

The 106-page/2,112-element stress fixture exposed repeated full-document layout when the editable text could not accept the exact printed-page layout. Every keystroke reset continuous coordinates and forced TextKit to lay out all text, even when the editor was already continuous.

The editor now resets the full layout only when leaving paged coordinates. Further edits in continuous view use native invalidation of the changed text and lay out the viewport. The natural-wrap validator retains unaffected paragraph line starts, shifts suffix offsets after edits, and invalidates its cache on geometry changes or ambiguous updates.

No changes were made to autosave timing, conflict detection, document format, Undo grouping, or screenplay text. A display-text caching experiment did not materially improve the measurement and was removed.

Validation includes independent natural-layout comparisons through 60 repeated paragraph edits, insertion/removal, Unicode, font changes, width changes, and empty text. Existing native editor, pagination, Undo, save/reopen, and document-safety tests remain required. The same release benchmark uses disposable copies, middle-of-script insertion, navigator and context inspector visible, and 20 keystrokes. It includes insertion, host layout, queued updates, and drawing. Results are machine/run-specific, not a universal latency guarantee.

Measured baseline warm median was 81.9 ms with a 228.4 ms first insertion. The retained layout fix initially measured approximately 54 ms warm with a 145.7 ms first insertion. Final release verification is recorded in the task report. This is a substantial reduction, not a claim of instantaneous typing or Final Draft performance parity.

Final retained-source verification: all 236 Swift tests, 37 Python tests, and 14 self-tests passed (287). The isolated 20-insertion release rerun measured a warm median of **55.7 ms** (54.2–66.7 ms warm range), with a **162.0 ms** first insertion. Relative to the recorded 81.9 ms baseline, the warm median fell about **32%**. Insertion preserves text projection and saves/reopens correctly in the benchmark. Build installation remains pending.
