# ScreenplayOS Edit — monotonic 24 fps transport clock (milestone 7, draft)

This branch is stacked on verified frame-cache PR #17. It leaves PRs #11–#17, FilmCraft interoperability PR #9, and `main` unchanged.

## Implementation

The previous still-image assembly transport measured time with `Date` and inferred its 24 fps position from elapsed wall-clock seconds. This milestone establishes an independent deterministic `NativeMonotonicPlaybackClock` in ScreenplayDomain, accepting a **caller-supplied monotonic nanosecond counter** and returning:

- The 24 fps timeline frame that should be presented at that exact monotonic time.
- The absolute monotonic deadline for the next frame transition.
- Correct paused/resumed, seek and end-of-sequence behavior.

Frame progress is calculated from the original monotonic start time rather than accumulating individual timer intervals. If a UI callback arrives late, the playhead jumps to the correct current frame rather than playing stale frames or slowing down. The calculations use integer frame/nanosecond arithmetic with explicit overflow caps; no floating-point frame accumulation.

The existing **still-image** Edit transport now uses `DispatchTime.now().uptimeNanoseconds` and this clock, replacing its `Date`-based rate calculation. Video-containing assemblies remain disabled for Play: paused verified PTS scrubbing still works, and the still-only boardomatic exporter remains unchanged.

## Tests

The new `NativeMonotonicPlaybackClockTests` check:
- No early frame transition at fractional 24 fps boundaries.
- Pause/resume without counting paused time; seek from an arbitrary frame.
- Correct frame skipping across a delayed callback, including end-of-timeline.
- Invalid frame ranges, safe behavior on an enormous forward clock jump and no integer wrap at `UInt64.max`.

The CI workflow compiles the full ScreenplayOS app and runs this suite alongside all prior assembly, video-preview, PTS, frame-rate and frame-cache suites.

## Honest performance and acceptance limits

This is **a clock and still-image transport**, not proof of continuous video playback. The existing SwiftUI Edit timer still redraws at an approximately 20 Hz cadence; a correct 24 fps position calculation does not establish presentation of all 24 video frames every second. AVFoundation decodes a frame on demand for video scrubbing, which remains intentionally paused. Verified video-frame caching retains full-source SHA-256 rehashing on each request and is not a low-latency video pipeline. Audio/video synchronization, frame-drop policy for decoded video, output rendering and proxy generation require their own milestones.

**Keep the branch draft until its exact-head macOS CI passes** and the transport has been visually tested on a disposable project. Nothing is uploaded or transmitted, no private materials are used, and no original FilmCraft code is copied.
