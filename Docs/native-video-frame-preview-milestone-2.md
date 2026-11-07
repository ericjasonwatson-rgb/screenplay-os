# ScreenplayOS Edit — Native video-frame preview (milestone 2, draft)

This development branch stacks on `feature/native-video-takes-20261106` (PR #12), itself stacked on native assembly PR #11. The FilmCraft compatibility experiment (#9) remains untouched.

## New capability

The Edit workspace can display **one decoded local MOV/MP4 frame at a paused timeline playhead**. The implementation:

1. Uses the existing, project-bound `NativeAssemblyClip` occurrence and its stable source Take identity. It never reconstructs identity by clip name or timing.
2. Computes the requested 24 fps sample as `sourceInFrame + localFrame` and refuses samples outside the recorded source range.
3. Accepts only a flat relative `Video Takes/` path. The containing directory and file must be ordinary non-symlinked local files.
4. Verifies SHA-256 against the saved Take fingerprint **before and after** AVFoundation decodes the frame.
5. Uses `AVAssetImageGenerator` with zero requested-time tolerances and checks the returned `actualTime` is within half a 24 fps frame of the requested timestamp, refusing a mismatched seek.
6. Converts the sampled image to in-memory PNG bytes for the SwiftUI preview. A request token prevents older asynchronous results from overwriting a later clip or playhead selection. Superseded tasks are cancelled so file hashing and decoding do not continue unnecessarily after the user scrubs elsewhere.
7. Leaves audio playback, realtime video playback, mixed-media export, external editor adoption and AI generation disabled.

## Model semantics

The current `sourceInFrame` represents a **24 fps timeline sample position**, not the exact coded-frame ordinal of every file format. Proper native footage conformance requires per-sample PTS/timebase inspection; VFR clips, mixed nominal rates, variable timestamps, interlaced footage, external audio timebases and variable-speed effects are not certified. A successful paused preview must not be described as frame-accurate editing of arbitrary camera footage.

## Test acceptance

A synthetic test generates two visibly distinct color boards, exports a local H.264 clip with the existing still renderer, imports it through the user-video importer, then decodes timeline samples in both halves of the clip. It verifies different returned image content, source-in offsets after a split, correct returned timestamp tolerance, out-of-range refusal, SHA tampering refusal, and refusal of a symlinked `Video Takes` directory. All fixtures are generated locally and deleted; no real screenplay, network access or provider is involved.

The expanded `Native Assembly Editor (macOS)` workflow builds the app and runs all `Native*` XCTest suites. **Do not claim preview release readiness before green CI on this branch and manual preview/scrubbing with disposable media.**

## Performance constraints

SHA-256 pre/post verification can read an imported file twice per preview request (up to 512 MB). This is deliberately conservative and *not yet a performant continuous viewer*. The UI leaves mixed media playback off. Later work may introduce a properly invalidated verified-asset handle and a bounded decode cache, but correctness and tamper detection take precedence here.

## Next gates

- Green macOS compilation and synthetic two-shot preview tests.
- Manual paused scrub, split, trim, resize and missing-media inspection.
- Frame-time mapping that preserves native PTS and rational frame rates, then deterministic video+still MP4 rendering.
- Audio synchronization, video caching and proxy policies, only after timebase conformance is verified.

## Current review state

PR #13 remains draft. The first parent video Take CI is green; the preview-specific macOS build and tests have not yet reported a pass. Preview performance on long camera originals, color-management fidelity, VFR seeks and comprehensive manual application testing remain open. Do not call this a full NLE playback feature.
