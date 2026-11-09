# ScreenplayOS Edit — Bounded video frame delivery (milestone 8, draft)

This research branch is stacked on the verified monotonic still-image playback clock in PR #18, with prior native editor PRs #11–#17 and FilmCraft PR #9 unchanged. It introduces the **policy and decoder adapter for video frame delivery**, not a user-facing realtime playback switch.

## Delivery contract

The `NativeVideoFrameDeliveryQueue` in ScreenplayDomain accepts a validated, immutable version-2 `NativeAssemblyProject` and editorial 24 fps timeline positions. It issues identity-bearing decode requests (source Take, unique occurrence, exact media SHA-256, relative source-in and timeline frame). A request is valid only for its active session token. The policy has:

- At most **two in-flight video decodes** and a **three-frame lookahead**.
- At most **four ready frames / 16 MiB**, with old frames retired.
- **Late decode completion refusal** rather than backfilling obsolete frames after a clock jump.
- At most **one-frame visual hold** of an already verified frame within the *same occurrence* when a new sample is late. The queue returns blank instead of holding another shot's image across an editorial cut, even if the adjacent occurrence refers to the same Take.
- Invalidated request tokens on seek, project replacement or stop. Failed/cancelled decoder slots are explicitly released without letting a forged token consume another request.
- No requests for still-image clips; existing still rendering continues outside the video decoder.

The model never decodes or reads media by itself. The `NativeVideoFrameDeliveryPipeline` actor connects requests to the existing `NativeVideoConformedPreview` reader, which samples the exact source presentation timestamp and checks the original media SHA-256. It validates the current source bytes **before presenting ready queued content** as well. The adapter cancels tasks that become obsolete as the monotonic clock advances.

## Current verification

Synthetic unit tests cover lookahead, pending/ready bounds, memory eviction, cut boundaries, reused Take identity, out-of-order completion, late-frame refusal, stale session refusal, oversized content and still-image isolation. The integration test creates a two-shot, local H.264 file, imports it using the existing Take importer, delivers frames 0 and 24 through the new adapter, checks shot-content difference and correct Take identity, then modifies the original local video and verifies no cached frame can be presented.

The CI workflow builds the full app and executes both new `NativeVideoFrameDelivery*` suites in addition to the earlier native editor, timestamp, preview, cache and monotonic clock gates.

## Release constraints

**Continuous video playback is not enabled.** This is an experimental delivery layer, not a realtime performance claim. A full-file SHA-256 is computed on each ready-frame presentation, and the AVFoundation preview decoder remains frame-on-demand; that is intentionally conservative but too slow for dependable 24 fps playback of large originals. No audio clock, resampling, proxy creation, GPU compositor or mixed-media export is included. The UI Play button remains disabled for video-containing timelines.

Before enabling video transport, we need a source-descriptor-bound verification session with explicit mutation invalidation, a proper seek/decoder queue with measured latency and frame-drop behavior, and manual tests on permitted camera footage (23.976, 25, 29.97, VFR, edit lists). Its display clock also needs measured cadence rather than a 20 Hz SwiftUI update timer. Audio synchronization is a subsequent, separate milestone.

Do not merge until the exact-head macOS CI run is green and a disposable macOS UI smoke test has been observed. No private production files, provider calls, media transfers or FilmCraft code are involved.
