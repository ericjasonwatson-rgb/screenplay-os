# Paragraph editing command boundary

Implemented 2026-09-14 in `ScreenplayDomain/PackageTextSession.swift`.

This is an in-memory command layer, not an enabled Mac editing workflow or a package writer. It accepts a complete file-byte snapshot supplied by a caller. It does not enumerate the filesystem, so the future loader must provide every file rather than selecting only the files it understands.

The first supported profile contains exactly `manifest.json` and `screenplay.json`. The manifest must declare core 1.0, contain the seven known string fields, and identify the same document UUID as the screenplay. The screenplay contains only `id` and `elements`; each paragraph contains only a unique UUID, recognized textual type, and text. This is an editing eligibility check, not full schema conformance (for example, timestamp semantics are not validated here).

The caller invokes replacement with an element UUID, expected session revision, exact expected text, and replacement text. Array positions are resolved internally and are never exposed as command identity. Text replacement preserves element IDs, types, order, and all untouched bytes. A no-op adds no history and keeps the revision. Successful edits, undo, and redo get fresh local session revision UUIDs, so an old request cannot become valid again after undo. These tokens are not persistent project revisions, retained ancestry, or protection against filesystem modifications.

Every companion file currently blocks editing, including empty notes, shots, settings, extensions, provenance, and a project envelope. Additional screenplay/element fields also block editing, including empty formatting runs, parsed scene metadata, revision marks, locks, and unknown fields. Unknown element types and page breaks are unsupported. Nothing is stripped to make a rich package fit the narrow profile. This deliberately excludes existing converted project packages until adapters can establish their reference, lock, inventory, and revision semantics.

Tests cover UUID targeting despite array order, Unicode text, exact undo/redo, unchanged original bytes, stale requests including undo returning to old text, unknown targets, no-op history, companion blockers, rich-element blockers, unsupported types, and case-insensitive UUID duplicates.

Next: adapt a real project package into this command boundary, preserving its complete snapshot and checking locks and anchored data. Then implement revision/inventory updates and a recoverable new-copy save transaction before exposing editing in the Mac app. Existing package previews and legacy saves remain unchanged.
