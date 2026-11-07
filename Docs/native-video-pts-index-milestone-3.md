# ScreenplayOS Edit — Source presentation timestamp index (milestone 3, draft)

This research branch is stacked on paused-frame preview PR #13; video Take import PR #12 and native assembly PR #11 remain separate drafts. FilmCraft interoperability PR #9 and `main` are unchanged.

## Why source time matters

PR #12 records integer frames at 24 fps for the editorial timeline, and PR #13 requests video stills using nominal `sourceInFrame / 24`. That is an approximation: 23.976 fps, 25 fps, 29.97 fps, B-frame decoding order, VFR clips and clip edit lists do not share the same frame ordinal system.

The new `NativeVideoPresentationIndex` deliberately separates three concepts: (1) the immutable source media SHA-256 and track ID, (2) the actual rational presentation timestamp of each compressed video sample, and (3) the editorial timeline position at 24 fps. It represents timestamps with integer CMTime value/timescale pairs; no timestamps are persisted as floating-point seconds.

## Implemented, isolated capabilities

- Pure project-domain index with version, source fingerprint, track ID, duration, strictly increasing presentation timestamps, bounded memory/sample count and exact rational comparison using CoreMedia's `CMTimeCompare`.
- Deterministic `sample(atTimelineFrame:)`: selects the last presentation timestamp **at or before** the 24 fps editorial time. This explicitly holds a source frame across sparse/VFR gaps rather than guessing a coded-frame ordinal.
- A read-only local `NativeVideoTimestampProbe` that verifies a local video's SHA-256, uses AVAssetReader to inspect its video sample presentation timestamps (including multi-sample buffers), sorts samples into presentation rather than decode order, verifies file fingerprint again and builds a validated index.
- Strict refusal for empty/duplicate/out-of-order/unrepresentable timestamps, missing or multiple video tracks, invalid duration, oversized sample sets and changed source files.
- Synthetic tests for rational 24000/1001, 25 fps and VFR source timestamps, JSON persistence and invalid sample sequences, plus a macOS test that renders a local H.264 file and enumerates its actual compressed sample timestamps.

## Deliberate non-features

**The index is read-only and not yet persisted as a trusted project artifact.** It does not silently rewrite older assembly sidecars, attach speculative identities to clips, change the existing paused-frame preview, or enable realtime playback, sound, proxies or export. Source timing is only authoritative for the exact video file hash and the inspected track.

`NativeVideoTimestampProbe` currently refuses multi-video-track files until track selection is explicitly defined. It also rejects negative or nonnumeric timestamps and duplicated presentation times instead of silently normalizing them. More exotic editor timebases, media edit lists and timestamp offsets may need dedicated mapping logic. Exact video-to-audio sync and high-quality VFR conform are not certified.

## Acceptance gates

1. Run focused macOS CI on this branch; no pass is claimed until the actual run is green.
2. Confirm that compressed H.264 sample PTS reads and JSON index serialization succeed and that the index matches known synthetic sample timing.
3. Test 24000/1001, 25, 30000/1001 and VFR real clips with explicit permitted source media, including audio/video track metadata and edit-list offsets.
4. Only then persist a source-hash-bound timing index, switch the preview decoder to the chosen original PTS, and verify source-in/source-out and frame selection after split, trim, duplicate and reopen.
5. Continuous playback and mixed video/still export are later milestones with separate clocks and output validation.

No private screenplay assets, media uploads, generation billing or external editor mutation are part of this branch.
