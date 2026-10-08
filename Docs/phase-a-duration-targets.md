# Phase A: optional beat and scene targets

2026-10-08. This increment adds authored planning durations to the legacy
filmmaking document. Phase A remains partial; it does not complete the wider
pipeline acceptance scenario or the additional Final Draft layout comparisons.

## Behavior and boundaries

- Outline beat cards and scene cards accept whole seconds or `m:ss`. Set/Return
  commits a change; Clear or a blank committed field removes it. Values must be
  1–86400 whole seconds. Invalid input is visible and never clamps a saved plan.
- The Script inspector has the current scene's target next to its script estimate
  and range comparison. Controls stay off the page and do not consume its height.
- Beat totals and scene totals are separate and show how many targets are set.
  They must not be added together. Scene targets are independent of beat targets;
  linking a scene never invents a duration or allocates a beat's time among scenes.
- Estimates for linked scenes deduplicate scene IDs. Missing estimates stay
  unavailable/untimed; partial estimates do not produce a misleading gap.
- Targets never change screenplay text, typography, pagination, clips or edit
  playback durations. Typing updates estimates while retaining authored targets.
- Set/Clear participates in document Undo/Redo and normal local save/recovery.
  Explicit scene duplication copies its plan onto a new heading identity. Scene
  deletion removes that target; Undo restores it. Reordering keeps the same plan.

## Storage and compatibility

These are additive optional fields in the existing monolithic format, not a new
native package schema. Existing versions 1.0/1.1/1.2 decode absent targets as unset
and keep their version. No automatic conversion or format-version bump occurs.
The optional fields are described in `Specs/open-screenplay-1.0.schema.json`:

- `outline[].target_duration_seconds`: integer seconds, omitted when unset.
- `scene_duration_targets`: optional object keyed by scene-heading element UUID,
  containing integer seconds. Display scene numbers and spine labels are not keys.

Decoder validation rejects invalid seconds and ambiguous case-variant UUID keys.
Lowercase UUID keys normalize to canonical uppercase; the existing round-trip
loss guard consequently protects that external source by opening a separate copy.
Dangling target UUIDs are retained but excluded from visible live-scene totals;
text deletion/type changes must not transfer a plan onto a different scene merely
because its displayed number is reused. Explicit Delete Scene clears its target.

Unknown fields still use the existing protected-copy behavior: original bytes
remain unchanged, but an editable legacy copy contains only supported fields.
This is **not** a claim of lossless unknown-field editing. No new Codable record
type is introduced. The experimental native package editor does not gain targets;
its full-project migration remains pending. The experimental converter's original
archive is not equivalent to editable target support. FDX explicitly warns that
it omits duration targets; retain the native project.

## Implementation

- `Sources/ScreenplayDomain/DurationTarget.swift:27`: validated input and platform-independent
  target commands. The Mac adapter supplies history, metadata and autosave.
- `Sources/ScreenplayDomain/ScreenplayDocument.swift:92`: optional persisted fields and
  validation while decoding older documents.
- `Sources/ScreenplayOSApp/ScreenplayViewModel.swift:1073`: undoable commands, estimate cache,
  stable scene identity during duplication/deletion.
- `Sources/ScreenplayOSApp/DurationTargetViews.swift:47`, `ContentView.swift:432`: Outline/Script
  controls, separate totals, honest estimate ranges and target comparisons.
- `Tests/ScreenplayEditorTests/DurationTargetTests.swift`: parsing, legacy defaults,
  new-field round trip, invalid persisted values, three-beat/three-scene 120-second
  plan, save/reopen, text edits/Undo/Redo, scene operations, missing estimates and
  unknown-field original-byte protection.

- `Sources/ScreenplayDomain/SceneDurationEstimate.swift:63`: an ephemeral scene
  cache reuses estimates for unchanged source records. This cache is not a saved
  document type and has no schema or migration payload. Equivalence tests cover
  edits, moved headings, merged/deleted scenes and an empty document.

## Verification

Automated and manual results are recorded below after validation. Fixtures are
synthetic/disposable; original screenplays are not edited.

Both `./Scripts/test.sh` and
`SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh` passed: **275 Swift
tests in 46 suites + 37 Python checks + 14 self-tests = 326 per configuration**.
Logs: `/tmp/phase-a-targets-debug.log`, `/tmp/phase-a-targets-release.log`.
`git diff --check` passed.

The paired native-window typing benchmark uses baseline `48fdb0d`, 20 middle-of-
script insertions, navigator and inspector open, and the same 106-page /
2,112-element disposable `/tmp/screenplay-audit-long.json` fixture. SHA-256:
`9d95d6036beed93a2c0b95a51bc92d427aa76ef47db6a5338b9ef64fb73cb428`. Command:
`SCREENPLAYOS_BENCHMARK_POSITION=middle SCREENPLAYOS_BENCHMARK_NAVIGATOR=1
SCREENPLAYOS_BENCHMARK_CONTEXT=1 SCREENPLAYOS_BENCHMARK_ITERATIONS=20
./Scripts/benchmark-typing.sh /tmp/screenplay-audit-long.json`.

| Configuration | Baseline median | Final median | Baseline first edit | Final first edit |
| --- | ---: | ---: | ---: | ---: |
| Debug | 83.04 ms | 85.28 ms | 231.49 ms | 227.87 ms |
| Release | 56.49 ms | 55.85 ms | 187.40 ms | 183.74 ms |

The first implementation rescanned every scene on each edit: Debug/Release
medians rose to 97.37/65.10 ms, with the increase concentrated in the layout
phase. The scene cache resolved that regression. Final medians are close to the
baseline in this single paired run; this is not a claim of improved typing speed
or hardware key-to-screen latency. Logs: `/tmp/phase-a-targets-before.log`,
`/tmp/phase-a-targets-after.log` (rejected), `/tmp/phase-a-targets-cached.log` (final).

Manual UI verification is pending in this source commit. No installed-app update
or public release is included.

### Live-check attempt — 2026-10-08

Launched `/private/tmp/screenplay-targets-audit/ScreenplayOS Timing Audit.app`.
Its executable matches the tested Release binary byte-for-byte and its source
revision is `53fa30a5c7f87af93696c716a38a63708b3ac149`. The accessibility tree
confirmed an empty Untitled Screenplay in Script mode with the inspector closed.
After requesting New/Open, automation timed out (`-10005 timeoutReached`); both
subsequent accessibility inspection and screen capture also timed out. The
sequence's final UI state could not be established. No live Set/Clear/Undo or
save/reopen success is claimed. User confirmation of the visible Mac state is
needed before further input. This does not establish that the application itself
froze. The installed application was not replaced.

### Live-check completion — 2026-10-08

Automation recovered on the next attempt; the earlier timeout's cause remains
undetermined. Used only `/private/tmp/screenplay-targets-audit/Three-scene-plan.json`
in the isolated audit bundle (source `53fa30a`). Observed:

- Script inspector initially showed S001 target 0:20, estimate 0:20–0:30,
  separate beat/scene totals 2:00 (3/3 set), and whole-script estimate 2:00–3:00.
- Set scene target to 0:40: scene total became 2:20 while beat total remained
  2:00; gap text correctly reported the target exceeded the estimate by at least
  0:10. Clear showed Unset and 1:40 (2/3 set). Toolbar Undo restored 0:40;
  another Undo restored 0:20 and the original scene total.
- Outline showed all three target fields (0:20, 0:40, 1:00), linked estimates,
  and independent totals. Attempting to Set 0 showed a validation message and
  left the plan unchanged. Set 0:30 changed only the beat total to 2:10.
  Clear reduced that total to 1:40 (2/3 set); toolbar Undo restored 0:30/2:10.
- Saved, quit the audit app, relaunched the bundle, and inspected the restored
  project. S001 remained 0:20, beat total 2:10, scene total 2:00 and estimate
  2:00–3:00. Undo was disabled on fresh launch. Direct file assertions confirmed
  beat targets [30, 40, 60], scene targets [20, 40, 60], and unchanged text for
  all six screenplay elements.
- Screenshots visually confirmed readable target controls in Outline and the
  Script inspector. The Script controls occupy the inspector, not page height.
  This was not an exhaustive screen-size or accessibility audit. Keyboard-only
  Set/Return and live typing-driven estimate changes remain automated evidence,
  not additional manual claims.

No code changes or additional test reruns were needed for this live check. The
prior 326 checks/configuration and paired benchmark remain the source validation.
The audit app is left open with the disposable project for review. The installed
app was not replaced; no release, signing changes or AI requests occurred.
