# ScreenplayOS Edit — native video Takes, milestone 1 (experimental)

Branch: `feature/native-video-takes-20261106`. Stacked on draft PR #11, separate from FilmCraft PR #9.

## What exists in this draft

- The first-party assembly record is now **schema v2**: each occurrence carries `mediaKind`, `sourceInFrame` and, for videos, a `sourceFrameLimit`. Source and occurrence identities are separate.
- Older still-image project sidecars (schema v1) are read and upgraded in memory. Their media remains still images with no invented source range. A later user save writes v2. Future/unsupported versions are refused.
- A video occurrence may be split at frame N: the new right-side occurrence receives a fresh UUID and begins at old source-in + N. A head trim increases source-in and decreases duration. Both preserve the Take UUID and media SHA-256, and refuse ranges exceeding the source limit.
- The user may explicitly select a local `.mov` or `.mp4`. The app checks that the file is an ordinary local file below 512 MiB, that AVFoundation reports a video track and finite duration, hashes the content and copies it to `Video Takes/<SHA-256>.<extension>` beside the saved screenplay. The copy's hash is checked independently before creating a distinct, assembly-local Take and edit occurrence.
- Video import is an explicit local operation; it does not modify the canonical ScreenplayOS Take ledger or submit prompts, transfer media over a network, or change source boards.
- The Edit UI provides an **Import MOV/MP4 Take** action and a one-frame head trim. The timeline stores video occurrences but **does not claim to display decoded video playback**. The current still-only MP4 exporter refuses any sequence containing a video Take.

## Important constraints

The current use of a source duration multiplied by 24 fps is an initial **conformed timing estimate**. It is not frame-accurate source conformance for 23.976, 25, 29.97, 60, variable-frame-rate, variable-timestamp or mixed-track material. Native video decoding, precise PTS/timebase handling, soundtrack preservation, audio/video synchronization, proxy policies and mixed video/stills export require a separate design and acceptance test. Playback remains disabled for timelines containing video so a moving playhead cannot be mistaken for actual video preview.

The new video Take is local to the assembly. No claim is made that it has been adopted into the versioned canonical Take ledger or is portable inside the screenplay package. Sidecar storage remains in Application Support, and source copies are beside the screenplay. Packaging and relocation require separate work.

## Safety and tests

- No automatic media identity reconstruction or reuse of occurrence IDs.
- Relative video paths restricted to a flat `Video Takes/` directory with `.mov`/`.mp4` extensions.
- SHA-256 checks on source and destination, plus refusal of symlink source files, non-file sources and unsafe destinations.
- Source limit and frame arithmetic validated on every mutation, with the total timeline limit unchanged.
- Synthetic tests exercise v1 migration, source-range split/head-trim/duplicate and refusal of invalid paths/limits.
- An integration test generates a local synthetic H.264 file with the existing still renderer, imports it as video and checks that re-opened v2 sidecars preserve its identity and that the still-only renderer refuses video.

**Release gate:** macOS CI on this branch must compile and pass. Actual video preview, robust edit-time conformance and real-media import observation are outstanding; keep the PR in draft. No change to `main` or upstream FilmCraft.
