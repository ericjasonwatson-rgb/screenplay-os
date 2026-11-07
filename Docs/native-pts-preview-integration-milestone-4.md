# ScreenplayOS Edit — Source-PTS-conformed paused video scrub (milestone 4, draft)

This is an isolated experimental branch stacked on the **verified** rational source timestamp index in PR #14. The existing still-image assembly (#11), imported video Takes (#12) and paused-frame preview (#13) stay unchanged.

## First integration

A paused video Take now obtains a verified, read-only source presentation index before requesting a frame. Instead of requesting the simple `(sourceInFrame + localFrame) / 24` second approximation as an AVAssetImageGenerator seek time, the editor asks `NativeVideoPresentationIndex.sample(for:localFrame:)` for the **actual source presentation timestamp** of the frame visible at that 24 fps editorial position.

A new `NativeVideoConformedPreview` actor holds at most four index entries, keyed by an absolute local video path and the **exact source SHA-256**. It does not load any index from an untrusted JSON document. The verified local source directory and file are checked before using cached state. The preview decoder itself verifies the source SHA before and after generating each image and refuses requests that return an incompatible timestamp. The UI cancels old requests and uses a request token to prevent stale frames appearing under a later playhead selection.

The original unindexed `NativeVideoFramePreview.preview` remains available to the earlier regression suite on the parent branch; the new Edit panel uses only the source-PTS-indexed path for video clips.

## Implemented checks

- Existing occurrence ID, Take ID and media SHA remain unchanged by a preview request.
- Split/trim source-in offsets are resolved using the index tied to the same video SHA.
- The source index uses actual decoded-sample presentation timestamps and rational CMTime values; the selection uses the latest source frame timestamp at or before the requested 24 fps edit time.
- Source media path must remain a flat relative `Video Takes/` path; symlinks or unexpected directory structure are refused.
- No frame is returned if original media content changes, source time is out of bounds or decoded actual time differs too much from the indexed source time.
- A synthetic H.264 test renders red and blue shots, imports the source, uses the new source-PTS path for two paused frames, verifies distinct imagery, tests source offset after a split and modifies imported bytes to confirm cached-index reuse still refuses the media.

## Deliberate limitations

This is **paused visual sampling only**, not realtime playback, waveform/audio synchronization, mixed-frame-rate timeline conformance or full finishing. The source PTS index is built by decoding all video samples at first use and repeated SHA reads can be expensive. A four-source session cache bounds memory but does not make an efficient professional viewer; the subsequent engine needs smarter invalidation and proxy/cache policies. Unusual VFR frame boundaries and media edit-list offsets still need independent real-camera fixtures. Imported video file source-frame limits are currently derived from an initial 24 fps duration estimate, which remains an approximation and can block some valid extreme source rates.

No FilmCraft code has been copied. Nothing is uploaded, paid, generated or adopted into the canonical screenplay. All edits continue to be project-local; no changes are proposed to `main`.

## Acceptance gates

1. Full macOS application compilation and focused original native assembly, video preview and PTS index suites.
2. New `NativeVideoConformedPreviewTests` synthetic 2-color source-PTS scrub, split-offset check and SHA-change refusal.
3. Manual paused scrubbing of permitted local 23.976, 25, 29.97 and VFR camera material with observed timestamp comparison and incorrect-file/permission cases.
4. Only after these checks: begin continuous playback and source-aware mixed-media export behind separate test gates.

Keep this PR draft until the exact branch head passes CI and manual UI inspection.
