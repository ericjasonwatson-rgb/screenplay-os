# Pipeline acceptance scenario

Adopted 2026-10-08. This is an acceptance specification, not a passing test report.
The complete automated scenario and external NLE round trip are not implemented.
Storykit remains ON HOLD. Existing safety and free-core rules take precedence.

## Stabilization gate and evidence

At `2ee74fd`, Debug and Release each passed 253 Swift tests, 37 Python tests and
14 executable self-tests (304 checks per configuration). `main` and
`v0.1.3-build26-source` were pushed and their remote hashes verified on October 7.
The original handoff's remaining Script Tab check passed on October 8 in the
isolated audit build: Scene Heading → Action; Undo → Scene Heading. Other live
checks and their limits are recorded in `build26-handoff-validation.md`.
The subsequent persistence fixes have automated regression coverage; they have
not had a separate live failure-injection pass. This governance commit changes
no runtime code and does not close the remaining stabilization backlog.

## Two-minute, three-scene sequence

Use only disposable synthetic projects and local media. Start a new untitled
project before testing because startup can reopen the last real screenplay.
Record each step as automated pass/fail, manually observed, or unverified; an
unimplemented step is not a pass. Use deterministic mocked AI responses only.

| Step | Automated acceptance to build | Manual checklist and evidence |
| --- | --- | --- |
| a. Outline | Three beats with target durations totaling exactly 120 seconds; save/reopen preserves optional targets | Three beat targets and a 2:00 plan total are visible |
| b. Script | Three linked scenes show targets beside estimates; typing changes estimates/gaps without changing targets; Undo restores state | Type in each scene and observe updated ranges and gaps |
| c. Shots | 3–5 shots per scene with planned durations; totals compare with scene estimate and target | Inspect shot and scene totals, including an unset duration |
| d. Boards | One board per shot; mock the explicit-consent generation/adoption flow for at least one board; stale results cannot replace newer work | Review prompt disclosure and candidate adoption without making a provider request |
| e. Animatic | Timed boards with dialogue/temp VO, music and effects lanes; offsets, gain, fades, scrubbing and scene loop; measure synchronization against a shared clock | Play with local audio, scrub, loop a scene, record measured drift and playback conditions |
| f. Takes | Import three local candidate clips per shot; selection substitutes media while retaining timeline timing and object references; Undo restores selection | Select/reject candidates, verify viewer/playback and missing-media behavior |
| g. Handoff | OTIO with video/audio, portable paths and stable shot/take metadata; keep EDL/FCPXML tests; add audio only where supported | Open in Resolve or Premiere; record app version, file, clip order, durations and audio alignment. Parser success alone is insufficient |
| h. Round trip | Import a trim plus two swapped scenes from edited OTIO/FCPXML; diff into proposals; accept updates shot timing, scene order and outline atomically; Undo restores all | Inspect proposals before acceptance; verify rejection, acceptance and Undo visibly |
| i. FDX | Export/reimport element types, text, styles and headings without loss within declared support; titles and dual dialogue handled or explicitly warned | Open in Final Draft if available; record title page, dual dialogue and formatting observations |
| j. Safety | Save/reopen, references and Undo at every mutation; preservation of unknown fields and original migration source; no implicit egress | Reopen relocated project offline; verify media and saved work; no AI calls during testing |

## Phase A — Trustworthy timing and interchange

Deliver FDX export and round-trip tests first. Treat title pages and dual dialogue
explicitly. Calibrate scene estimates against the approximate one-page/minute
heuristic without presenting it as measured performance time. Placeholder clips
must not count as measured runtime. Expose ranges and unknowns honestly.

Compare Defenders (observed 18 ScreenplayOS pages versus 15 Final Draft pages)
and two other disposable scripts before proposing any line-pitch change. Record
fonts, layout settings and effects on scene/page locks. Propose the change before
applying it; do not silently repaginate production-locked work.

Add optional beat and scene targets with Outline and Script plan-versus-estimate
displays, persistence, migration and Undo coverage.

## Phase B — Audio in the animatic

Add audio records and WAV/AIFF/M4A/MP3 import, three lanes, waveform thumbnails,
AVFoundation synchronized playback, per-item gain and fades. Temp VO may link to
a dialogue element. Local scratch recording is optional and requires normal Mac
microphone permission. No AI voice integration in this phase.

## Phase C — Takes

Add ordered takes and a lossless migration of board image versions. Import local
stills/video; select/reject takes and substitute the selected media while retaining
timing. Expose provenance, rights/consent notes, optional cost/currency and scene
cost summaries. Do not sum different currencies without an explicit policy.
No new generation-provider integrations; record the source tool of imported files.

## Phase D — Handoff and round trip

Export media-linked OTIO with video/audio and stable IDs. Import edited OTIO/FCPXML
using identity metadata; unmatched or ambiguous clips stay unresolved proposals.
Never infer acceptance or silently mutate script order. Apply accepted decisions
as one undoable transaction with downstream reference repair.

## Evidence required per phase

- Small commits and a Docs evidence note listing changed files/lines.
- Named tests and exact pass counts; legacy 0.1.3 migration, unknown fields,
  Unicode, missing media, failure recovery and Undo as applicable.
- Actual manual observations, separately from assumptions and missing checks.
- Run `Scripts/benchmark-typing.sh` on the same disposable long-script fixture
  before and after runtime changes. Record fixture, revision, configuration,
  workload, repetitions and measured timings. Harness timings are not hardware
  key-to-screen latency. Investigate any regression before closing the phase.
- No AI calls, charges, key exposure, release publication or signing changes.
  Commit before packaging. Keep original screenplays intact.

Governance-only edits do not require a new typing benchmark; no runtime or layout
has changed. Phase A must establish its measured baseline before implementation.
