# ScreenplayOS Edit — multi-rate source video acceptance (milestone 5)

This branch is stacked on source-PTS-indexed paused preview PR #15. All previous native-editor PRs (#11–#14) and FilmCraft interoperability PR #9 remain unchanged.

## Acceptance objective

The editor currently uses a 24 fps editorial timeline while video may have a different native frame rate or irregular presentation timestamps. This test milestone generates its own short H.264 media with precisely specified presentation timestamps on the macOS runner and checks **the decoded source sample PTS**, not just a mathematical model.

The new XCTest fixture creates local sources at:
- **24000/1001 (~23.976 fps)** — timeline frame 1 still displays source sample 0.
- **25 fps** — timeline frame 1 displays source sample 1.
- **30000/1001 (~29.97 fps)** — timeline frame 1 displays source sample 1.
- **Irregular VFR-style timing** — sparse source presentations at edit frames 0, 1, 3, 10, 20, 21 are held across gaps until a later source sample is presented.

The test writes H.264 using AVAssetWriter, reads its actual sample presentation times through the trusted `NativeVideoTimestampProbe`, confirms all expected rational timestamps survived encoding, imports it into `Video Takes/`, then exercises the source-PTS-conformed paused viewer on two deliberately different images.

**This is regression code, not a user-facing feature switch.** All media is synthetic, locally generated and cleaned up.

## Important limits

- The fixtures test explicit rational presentation time, not arbitrary real-camera footage or every H.264 encoder's edit-list semantics.
- Tests use short, uncompressed-in-memory colored frames written to H.264. Color and temporal compression can change pixel values; only visual distinction is asserted, not bit-for-bit image equality with source pixels.
- A successful test does not establish realtime video performance, video/audio synchronization, mixed-media export, 10-bit HDR fidelity or timecode interoperability.
- The current `NativeVideoTakeImporter` still uses a duration×24 estimate for the overall source-frame bound; a later source conformance milestone must version that range policy explicitly.
- Video-frame preview's first PTS indexing step decodes a whole source and can be expensive; no background scanning or cached proxy generation is introduced here.

## Evidence and gates

The feature branch has a dedicated macOS GitHub Actions test step `NativeVideoRateConformTests`. The branch remains draft until a real CI result passes on its exact head. Do not merge or enable continuous playback automatically; manual inspection and real-rate camera fixtures remain open.

No private creative materials, external files, AI models, media uploads, provider payments or original FilmCraft code are used.
