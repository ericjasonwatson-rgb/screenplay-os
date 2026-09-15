# Package Find/Replace

Command-F or Find opens the package editor's search controls and focuses the query. Next/Previous and Command-G/Command-Shift-G navigate matches with wraparound; Return in the query advances. Done or Escape closes the controls and returns to writing. Match case is optional and off by default.

Search is literal and matches substrings within authored paragraphs, never across paragraph identities. It includes all supported paragraph types. Regex and whole-word options are not implemented. Unicode matching respects complete grapheme boundaries, so a query cannot replace only part of an emoji or combining-character sequence. Canonically equivalent composed/decomposed accents are supported by Foundation matching. An empty query has no matches; an empty replacement deletes matched text without deleting the paragraph.

Replace is enabled only when the writing selection exactly matches a current result. It replaces that selection and retains a selection around the replacement. Replace All validates and replaces every current match in one domain transaction. Both preserve paragraph IDs, types, ordering, and untouched JSON bytes. Results are computed against the current document revision; stale or invalid requests fail before publishing any changes. Identical replacements produce no history entry. Undo/Redo uses the existing exact-byte history and recorded selection.

Query, replacement, options, and match selection are transient UI state. The source package remains unchanged until the existing separate-copy save. Recovery retains the edited screenplay through the same local path. Undo/Redo while a package text field is active uses that field's native history rather than undoing screenplay edits.

The full suite passed 128 Swift tests, 37 Python tests, and 14 self-tests. Find-specific tests cover matches across several paragraphs, case sensitivity, atomic Replace All undo/redo, stable IDs, Unicode, empty/no-op behavior, stale revision rejection, next/previous wraparound, selected-match replacement, and source-safe save/reopen.

The release build succeeded. Native verification remains pending: macOS reported the app running but repeated window-reopen requests timed out (AppleEvent -1712). Automated native text-view tests passed; they do not establish the complete on-screen search-field/menu workflow.
