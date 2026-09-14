# Local recovery for experimental package edits

Package editing writes a separate recovery record under Application Support/ScreenplayOS/Recovery/Packages. Tests inject an isolated directory. The original package is never used as the recovery destination.

Typing schedules a snapshot after 500 ms without another change. Recovery captures all supported package files with the pending paragraph text applied to a temporary session, without changing the live Apply/Undo boundary. Apply, selection changes, Undo/Redo, Save, and Close also update or flush recovery. The status distinguishes pending, saved locally, and failed. A crash before the scheduled write completes can lose the latest changes; this is not a per-keystroke durability guarantee.

Each editor has its own UUID record. Publication writes a private sibling temporary file, handles short/interrupted writes, calls fsync and macOS F_FULLFSYNC, renames it over only that editor's previous record, then synchronizes the directory. Failures leave the preceding published record or the newly published record, plus any pending file; no automatic cleanup deletes partial output. Power loss and filesystem/device behavior are not simulated by the in-process tests.

File > Recover Package Edits lists valid records on startup and offers Refresh Recovery List. Recovery validates the version and minimal editing profile, materializes a new private working package from the stored bytes, and opens it with an unsaved status. It works without the original path and can save to a separate new copy. It does not merge with or overwrite an externally changed original. The record retains the original source path for context/default save location. Undo history is not recovered; the latest recoverable text is.

Successfully saving a copy, explicitly discarding edits, or undoing back to a clean state removes that session's recovery record. Other editor sessions are unaffected. A failed save retains recovery. Corrupt or unsupported records are left untouched and omitted from the valid-record list. Materialized working packages and incomplete temporary records are retained; storage cleanup and a recovery-management browser remain future work.

The close/quit prompt also offers Keep Recovery for Later. It permits closing only after the recovery write succeeds and retains the record for the next launch. This is distinct from saving a user-selected package or explicitly discarding changes.

The application Quit menu and Command-Q now explicitly invoke the same unsaved-work decision as Close before requesting termination. The application delegate still guards termination requests from elsewhere. A successful explicit decision is passed through once to avoid prompting twice.

Tests cover unapplied Unicode text, restoring through a newly constructed editor with the original removed, saving a recovered copy, interrupted record replacement, recovery-write errors, cleanup after Undo/save, debounce behavior, and independent simultaneous sessions. This remains limited to the minimal package editing profile.
