# Phase A timing increment — 2026-10-08

## Changes

- `Sources/ScreenplayDomain/SceneDurationEstimate.swift`: replaced action reading
  speed with a fixed planning-page heuristic: 60 character columns and 54 lines,
  word wrapping and explicit line breaks, one spacing line per nonempty action
  paragraph. A page estimates 45–75 seconds, midpoint 60. Dialogue remains
  120–180 words/minute. Ranges round outward to five seconds with the existing
  5–10-second floor. Empty/heading-only scenes stay unknown.
- `Sources/ScreenplayDomain/ScenePlanningTimeline.swift`: shared clip eligibility
  excludes shot placeholders, omitted/placeholder status, invalid durations, and
  unassembled media. Board durations remain planned timing, not measured runtime.
- `Sources/ScreenplayOSApp/EditPlayback.swift` and `SceneTimingDisplay.swift`:
  playback and summaries use eligible clips. Untimed scenes remain selectable.
  Excluded authored material is not silently replaced by an estimate.
- `Sources/ScreenplayOSApp/ScreenplayViewModel.swift`: clip-only CSV now uses the
  same derived clip timing and excludes omitted/placeholder rows. EDL/FCPXML
  already use the shared timeline. Estimates are not authored CSV clip rows.
- `SceneDurationTests.swift` and `ImportAndEditTests.swift`: three new tests for
  page normalization, combined dialogue/action ranges, eligibility, invalid
  durations, the Estimates toggle, CSV/FCPXML output, and unchanged source data.

No document schema, migration, printed layout, page lock, original screenplay,
stored clip or Undo history changes are required for these derived calculations.

## Assumptions and limits

This is a provisional planning normalization, not empirical calibration against
filmed performances. A dense action planning page previously produced several
minutes from prose-reading speed; it now centers on the requested one-page/minute
rule. Actual staging, pauses, montage and performance can exceed either bound.
The 60-column/54-line page is independent of current printed layout and does not
resolve the observed 18-versus-15-page Defenders discrepancy. No line-pitch change
was made. Future timing targets and measured takes must remain separate values.

## Automated and performance evidence

Debug and Release each passed 262 Swift tests, 37 Python checks and 14 executable
self-tests: **313 per configuration**. Logs: `/tmp/phase-a-timing-debug.log` and
`/tmp/phase-a-timing-release.log`. Native timeline rendering,
selection, save/reopen and Undo regressions run as part of the existing suite.
The benchmark uses the same 106-page/2,112-element disposable fixture as the FDX
increment, middle edits, Navigator and Context on, Focus off, 20 iterations and
navigation settling off. Logs: `/tmp/phase-a-timing-before.log` and
`/tmp/phase-a-timing-after.log`. Harness timings are not physical key-to-screen
latency and do not prove acceptable real-time responsiveness.

## Manual observations

No new live UI pass or installed-app replacement in this increment. The native
rendering test is automated evidence, not a manual visual review. No AI requests,
release publication or signing changes occurred.

## Remaining

Beat/scene targets and safe migration, two additional Final Draft layout
comparisons, and full Phase A acceptance remain. The lock-preserving line-pitch
decision is recorded below. Audio/takes/NLE round trip are later phases.

## Paired benchmark results

Baseline source: `d1dc114`. After: this increment. Same fixture SHA-256 as the
FDX increment: `9d95d6036beed93a2c0b95a51bc92d427aa76ef47db6a5338b9ef64fb73cb428`.

| Configuration | Before median | After median | Before first edit | After first edit |
| --- | ---: | ---: | ---: | ---: |
| Debug | 84.37 ms | 85.69 ms | 237.03 ms | 228.74 ms |
| Release | 55.73 ms | 54.39 ms | 175.86 ms | 170.51 ms |

The small differences do not establish a meaningful speed change in a single
paired run. No material regression was observed; typing latency still merits
separate work. Tests passed after the CSV consistency fix as well as the timing
model changes.

## Lock-preserving line-pitch decision — 2026-10-10

Retain legacy layout as the only production layout. Do not expose, persist or use
the header-continuation candidate to create production page locks yet. Existing
documents and locks continue to reopen with their current geometry and labels.

The candidate is the leading compatibility profile: it matches the 18/20/15 page
counts across the action, dialogue and Defenders samples, and its generated
dialogue fixture matches all 20 corresponding Final Draft body-text boundaries and
baseline coordinates. It also passed the recorded real-document stress, source
projection, save/reopen, PDF and typing checks. That evidence is sufficient to keep
developing the profile, but not to call it general Final Draft compatibility. Only
the synthetic dialogue document has a complete page-by-page rendered reference;
the Defenders evidence is a page-count comparison, and the Chickamauga review did
not include a corresponding Final Draft PDF boundary comparison.

Before exposure, add two independent, rights-cleared Final Draft PDF/FDX pairs with
mixed action, dialogue, transitions, rich text and long continuations. Compare exact
page boundaries, line wrapping, baselines, continuation placement and total text.
Then define an explicit document-level conversion with a page-change preview.
Never change an existing or locked document implicitly. The candidate remains
initializer-only and disabled by default until those checks pass.
