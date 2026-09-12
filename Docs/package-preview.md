# Read-only package preview in the Mac app

## Native interaction check, 2026-09-12

Native verification passed with a synthetic two-scene package. Opening displays the experimental/read-only notice and script text without clipping. Both scene buttons scroll to the corresponding heading, including returning to the first scene. Save, Save As, and export are disabled during preview; Escape closes it and returns to the same draft, document path, and text. The initial shared ScrollViewReader failed to target the text reliably. The corrected reader wraps only the screenplay scroll view, with a separate navigation request so repeated scene activation can scroll again. Release build passed. This verifies the bounded preview journey, not package editing or complete format conformance.

The Open command now accepts experimental `.screenplay` directories alongside legacy JSON and FDX. Packages open in a separate preview sheet with script text, scene navigation, a read-only/experimental label, and Close Preview. The editable document, save URL, recent-document history, and undo stack are not replaced by this path.

The preview uses its own display model, never `OpenScreenplayDocument` or the app's normalizing decoder. It contains selectable text rather than an editable text view. Main app menu commands are disabled while it is shown, and the editor's local keyboard monitor ignores preview events. Closing the sheet returns to the existing draft. The package is never passed to autosave, Save As, or the editable document's persistence path.

## Verification boundary

The native Foundation/CryptoKit reader checks the supported project/core version declarations, expected file membership, safe inventory paths, regular files/no symlinks, payload byte sizes and SHA-256 hashes, original-source digest, matching document identity, and unique paragraph IDs. It rejects duplicate JSON keys in the objects it interprets. It rereads observed files before returning to detect changes during loading. This is not an exclusive file lock, an authenticity signature, or full destination-schema/semantic conformance validation.

Unknown paragraph types render their original text neutrally. Blank paragraphs and Unicode text are retained. The preview shows script text and scene navigation only: title-page layout, pagination, styling runs, production locks, notes, shots, boards, and editing workspaces are not rendered. These limitations are stated in the sheet. No Python runtime or schema-library dependency is required by the Mac preview.

To bound this initial reader, each file is limited to 32 MiB, total loaded bytes to 128 MiB, and interpreted JSON nesting to 128 levels. Larger/unsupported/incomplete/changed packages fail with a message that the current screenplay was not replaced. Finder's root `.DS_Store` is tolerated; other unexpected files are rejected. System path aliases such as `/var` versus `/private/var` are normalized after checking the selected package is not itself a symlink.

This change does not register a Finder document type or change default saves. Open a package through File > Open. The next step toward package editing still requires an editable preservation model, guarded transactions, and tests for unknown data, production locks, and unsupported features; a read-only preview is not format conformance.
