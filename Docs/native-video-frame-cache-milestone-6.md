# ScreenplayOS Edit — bounded verified frame caching (milestone 6, draft)

This branch is stacked on frame-rate source acceptance PR #16, which passed macOS CI using local 23.976, 25, 29.97 and irregular-timestamp H.264 fixtures. Native editor PRs #11–#15, FilmCraft experiment PR #9 and `main` remain untouched.

## What this change does

The previous paused-preview pipeline used a source-hash-bound PTS index but re-created an AVAssetImageGenerator decode for each repeated request. This branch introduces a **byte- and count-bounded in-memory LRU of decoded PNG frames** scoped to the local file's standardized path, exact media SHA-256, and selected rational presentation timestamp (`value` and `timescale`).

- Maximum 16 decoded frames, maximum 16 MiB of PNG payloads, with least-recently-used eviction; oversized stills are never added.
- The existing verified-source gate still reads and hashes the **current original video file before EVERY cached hit**. A cache is never an authorization to read changed source media.
- A decoded-frame cache hit reconstitutes the **current occurrence-local** requested frame and source sample index. Split and duplicated occurrences can share identical source pixels while retaining separate occurrence IDs, Take identity and original source-in offsets.
- Misses continue through the existing source-PTS-selected decoder, which verifies source SHA before and after extraction and checks the actual returned timestamp.
- The actor's `clear()` invalidates both the PTS indexes and decoded frames and increments a generation token. Async PTS probes and decodes already running before project navigation cannot populate a newly cleared cache afterward.
- The existing Edit-panel cancellation/request-token logic is unchanged. Neither realtime video playback nor audio/export is enabled.

## What this does NOT do

**This is a decode reuse optimization, not a production-speed player.** A source file of up to 512 MiB is still hashed on each cache lookup. First source indexing may decode the entire media stream. There is no disk cache, proxy generation, GPU frame pipeline, audio sync, background prefetch or source-frame-rate replacement. Media and take identity are unchanged, and no persistent assembly schema migration is needed.

The next milestone can evaluate a file-descriptor-bound media verification session with explicit invalidation, then build a bounded decode/presentation queue and monotonic continuous playback clock. None of those is enabled here.

## Automated tests

- `NativeVerifiedFrameCacheTests`: byte budget, count limit, least-recently-used eviction, oversized frame refusal, source path/SHA/PTS isolation, replacement accounting and clear.
- Expanded `NativeVideoConformedPreviewTests`: synthetic two-color H.264 is imported; source frame is decoded once and reused after a split and across repeated requests; cache metrics confirm hits and size bounds; source mutation is still rejected even if the matching frame was cached.
- Existing `NativeAssembly*`, `NativeVideoFramePreview*`, `NativeVideoRateConform*`, `NativeVideoPresentationIndex*`, `NativeVideoTimestampProbe*` suites remain gates in the macOS workflow.

All fixtures are generated locally. No private footage, external egress, paid AI generation or FilmCraft code is involved. **Remain draft until CI on the exact branch head passes and manual macOS UI checks are performed.**
