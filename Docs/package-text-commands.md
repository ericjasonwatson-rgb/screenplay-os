# Paragraph editing command boundary

Native loading and new-copy persistence for this minimal profile are now implemented separately; see `package-edited-copy.md`. Mac UI integration is implemented; richer project revision/inventory support remains pending.

Implemented 2026-09-14 in `ScreenplayDomain/PackageTextSession.swift`.

This is the in-memory command layer used by the minimal Mac package editor; persistence remains in a separate adapter. It accepts a complete file-byte snapshot supplied by a caller. It does not enumerate the filesystem, so the future loader must provide every file rather than selecting only the files it understands.

The first supported profile contains exactly `manifest.json` and `screenplay.json`. The manifest must declare core 1.0, contain the seven known string fields, and identify the same document UUID as the screenplay. The screenplay contains only `id` and `elements`; each paragraph contains only a unique UUID, recognized textual type, and text. This is an editing eligibility check, not full schema conformance (for example, timestamp semantics are not validated here).

The caller invokes replacement with an element UUID, expected session revision, exact expected text, and replacement text. Array positions are resolved internally and are never exposed as command identity. Text replacement preserves element IDs, types, order, and all untouched bytes. A no-op adds no history and keeps the revision. Successful edits, undo, and redo get fresh local session revision UUIDs, so an old request cannot become valid again after undo. These tokens are not persistent project revisions, retained ancestry, or protection against filesystem modifications.

Every companion file currently blocks editing, including empty notes, shots, settings, extensions, provenance, and a project envelope. Additional screenplay/element fields also block editing, including empty formatting runs, parsed scene metadata, revision marks, locks, and unknown fields. Unknown element types and page breaks are unsupported. Nothing is stripped to make a rich package fit the narrow profile. This deliberately excludes existing converted project packages until adapters can establish their reference, lock, inventory, and revision semantics.

Tests cover UUID targeting despite array order, Unicode text, exact undo/redo, unchanged original bytes, stale requests including undo returning to old text, unknown targets, no-op history, companion blockers, rich-element blockers, unsupported types, and case-insensitive UUID duplicates.

Structural commands for the same minimal profile are documented in `package-structure.md`. Rich project editing still requires complete snapshot preservation, lock and anchor adapters, and revision/inventory updates. Existing rich package previews and legacy saves remain unchanged.
