# Package editing foundation

The next command layer is now implemented for a deliberately narrow minimal-package profile; see `package-text-commands.md` for stable-ID targeting, local revision checks, and editing blockers. The minimal profile is now connected to Mac editing and separate-copy saves; see `package-editor-ui.md`.

Implemented 2026-09-13: `ScreenplayDomain/PreservedJSON.swift` supplies a native, in-memory JSON preservation primitive and undo/redo session. It now underpins the minimal package editor and its separate-copy writer.

The parser indexes string-value byte ranges while validating JSON syntax and rejecting duplicate decoded keys. Numbers are validated lexically and never converted to floating point: large integers, long decimals, and large exponents retain their exact original tokens. Object keys and string comparisons use exact Unicode scalar identity, including distinguishing composed and decomposed text. String escapes are decoded only for lookup/comparison; opening never rewrites the bytes.

A compare-and-replace request identifies a string by typed object-key/array-index path and supplies its expected current text. It replaces only that string token, validates the candidate before accepting it, and leaves all other bytes unchanged. Stale values, missing/non-string targets, invalid UTF-8, malformed JSON, and duplicate keys fail without changing state. No-op replacements retain the original escape spelling and add no undo entry. Undo/redo restores exact prior byte states; a new successful edit clears redo. Input is limited to 32 MiB and nesting below 128 levels.

The API is a low-level preservation mechanism, not a screenplay command. Array indexes are temporary paths into a particular byte state, not canonical element identity. Before UI integration, a screenplay command must resolve a stable element UUID against an expected document revision, establish whether the edit is supported, and repair understood ranges/references in the same transaction. Unknown required semantics, unsupported production locks, formatting runs, and text-range anchors cannot be bypassed merely because their bytes can be retained.

Rich package editing remains disabled. This primitive neither validates package conformance nor updates file inventories, project/object revision ancestry, retained generations, or migration provenance. Whole-package transactions, external modification detection, failure recovery, and bounded production undo storage remain separate work. Never write these modified JSON bytes into an existing package on their own.

Tests cover exact surrounding-byte preservation, huge numeric tokens, nested unknown data, Unicode and escape retention, empty replacement text, stale comparison, absent targets, no-op/history behavior, undo/redo branching, distinct canonically equivalent keys, typed array paths, malformed syntax, duplicate escaped keys, invalid UTF-8, and nesting limits.
