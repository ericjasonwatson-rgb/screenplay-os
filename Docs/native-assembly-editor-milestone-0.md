# ScreenplayOS Edit — first-party native assembly, milestone 0

Branch: `feature/native-assembly-editor-20261106`  
Base: Siri/image integration PR #8. **Independent from experimental FilmCraft PR #9.**

## What is implemented

A separate **Native Assembly · Preview** mode sits beside the existing Edit scene-spine view. It uses only selected Board Image Versions already present in the opened screenplay, as an offline still-image assembly.

- Versioned first-party `NativeAssemblyProject` and `NativeAssemblyClip` records in ScreenplayDomain. Every timeline occurrence has its own ID, separate from the immutable Take (image version) ID. Scene, shot, board, generation job, media and prompt fingerprints are retained where available; no raw prompt or credentials are saved into the assembly.
- A portable `Board Images/<basename>` media reference and integer 24 fps frame lengths (no floating-point trim math).
- Local project-bound JSON sidecars in Application Support, with a maximum size, version validation, duplicate-identity refusal, and atomic writes. The screenplay's canonical boards and Take ledger are not modified by an assembly edit.
- Assemble selected boards, playback/scrubbing, frame-by-frame duration trims, split, duplicate, reorder, undo, save/reopen. A split **creates a new occurrence ID** while preserving its source Take and fingerprints; a duplicate likewise gets a new occurrence ID.
- Explicit local MP4 export of selected still images at 1280×720, 24 fps, H.264 using AVFoundation. Every input is checked against its saved SHA-256, symlinks and non-Board-Images references are rejected, and export refuses a filename already in use. Export is blocked if board source revision changed after assembly. Output is limited to five minutes.
- Synthetic XCTest coverage for save/reopen, independent occurrence identity, split, trim, duplication, reordering, unsafe media paths, stale source revisions and wrong-project sidecars.
- Dedicated macOS CI compiles the entire executable and runs the focused tests.

## Security and data ownership

The screenplay source remains authoritative; the assembly is an **explicit editable derivative**. Board changes do not silently replace the source Take in an existing assembly. The app refuses exporting a stale assembly until it is deliberately rebuilt. The preview and renderer read local files only; no AI provider calls, background uploads or paid operations occur.

The current sidecar is in local Application Support, **not yet within a portable screenplay project package**. Do not claim moving the screenplay to another computer also moves the assembly. Production-ready package migration needs an explicit project-format version, move/rename tests and migration/rollback support.

This is ScreenplayOS's own editing model and SwiftUI interface, with a deliberately small Apple-platform offline H.264 export path. **FilmCraft code has not been copied into this branch.** For later Rust engine integration, evaluate `filmcraft-time`, `filmcraft-project`, `filmcraft-edit`, `filmcraft-render` and codec/export crates individually; honor MIT/Apache-2.0 and all upstream notices. Remove ArtCraft trademarks and follow the upstream brand license in any eventual redistribution. Keep one canonical ScreenplayOS occurrence/provenance model rather than round-tripping identities through an external editor.

## Important limitations and acceptance status

- This is a **still-image boardomatic**. It does not yet decode video Takes or sync, mix or render audio in the new mode. The old Edit scene spine and its audio functionality remain separate and unchanged.
- Native Assembly is scene-scoped. Only selected images are included, and boards without a selected image are skipped. No automatic scene-wide media adoption occurs.
- The MP4 path currently uses AVFoundation, not FilmCraft Rust rendering; the CLI/GUI FilmCraft interop acceptance in PR #9 is independent.
- Preview verification and MP4 generation need manual observation with **disposable local assets** on macOS, including playback in QuickTime, visual aspect ratio and A/V expectations (silent by design).
- CI passing is required before any build-readiness claim. No new results should be represented as passed until GitHub Actions actually reports success.
- A standalone compiled Rust media adapter, native video Takes, audio, compositing, proxies, media cache, portable package files and pro finishing remain subsequent milestones.

## First acceptance scenario

1. Open a disposable screenplay with a scene, two selected board images under `Board Images` and valid source fingerprints.
2. Switch Edit to `Native Assembly · Preview`; assemble, play, scrub, split one occurrence and trim by one frame.
3. Confirm the two split occurrences share the same Take ID but have distinct occurrence IDs.
4. Close/reopen the app and re-enter Native Assembly. Verify order, durations, IDs and fingerprints are unchanged.
5. Export a local, silent MP4 and inspect its duration, frame rate and image order in a separate player.
6. Change a source board or its SHA. Confirm the existing assembly stays available for review but export is refused until rebuild.
7. Attempt missing, symlinked, modified and external media; confirm no output is created and no source document is changed.
8. Confirm that PR #9's strict unmodified-FilmCraft failure is unchanged.

## Next engineering steps

1. macOS CI build and focused tests; fix compile/runtime failures, and test actual MP4 export with synthetic PNG files.
2. Versioned portable assembly packaging and explicit two-way bindings to Board/Shot selections with clean Undo.
3. Reconcile existing Edit audio lanes and generated video Takes with a unified timeline clock.
4. Separate Rust media engine behind a stable local boundary; retain this first-party canonical project schema and explicit action permissions.
