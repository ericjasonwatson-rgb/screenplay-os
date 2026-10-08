# Phase A, first increment: FDX export — 2026-10-08

This completes the first bounded interchange increment, not all of Phase A.

## Changes

- `Sources/ScreenplayFDX/FDXExporter.swift:6`: screenplay-only FDX serializer,
  paragraph types, Unicode text, resolved bold/italic/underline/strikeout, explicit
  page boundaries via StartsNewPage, and a separate standard title-page section.
- `Sources/ScreenplayOSApp/FDXExport.swift:7`: immutable export snapshot for the
  legacy and package editors, including pending package draft text. Review of
  limitations precedes the save panel. Source/current-document overwrite is
  rejected; existing export replacement uses a checked atomic write.
- `Sources/ScreenplayOSApp/ScreenplayOSApp.swift:111`: File → Export Final Draft FDX.
- `Tests/ScreenplayEditorTests/FDXExportTests.swift:7`: six regression tests.

The native format, stored text, IDs, history, and page locks are unchanged.
Exported paragraph IDs identify their original elements, but reimport creates a
new document and records them as external FDX IDs; this is not project round trip.
Consecutive/trailing breaks and nonempty page-break elements fail explicitly.
XML-invalid control characters fail rather than disappearing. Title-page wording
is kept separately; author/contact field roles and layout need review on reimport.
Dual-dialogue simultaneity cannot be recovered from a prior sequential import and
is explicitly warned. Custom font/layout, revision marks, page locks, notes and
filmmaking metadata are not exported. Export does not transmit any content.

## Automated checks

Debug and Release each passed 259 Swift tests, 37 Python checks and 14 executable
self-tests: **310 per configuration**. The six new tests cover all element types,
Unicode scalar preservation, overlapping styles, explicit breaks, title separation,
invalid-input refusal, the full Defenders fixture round trip, pending package
text, unchanged session/history, original-source protection, and export conflicts.

Logs: `/tmp/phase-a-debug.log`, `/tmp/phase-a-release.log`.
An initial test compile error (a missing inner `try` in a Testing macro) was fixed
before these passing runs. No production importer changes were required.

## Performance measurement

Used `Scripts/benchmark-typing.sh` before and after this increment, same 106-page,
2,112-element disposable fixture, middle insertion, Navigator and Context enabled,
Focus off, 20 iterations, navigation settling disabled. Fixture SHA-256:
`9d95d6036beed93a2c0b95a51bc92d427aa76ef47db6a5338b9ef64fb73cb428`.
Baseline source: `b52a298`; after: this increment. Logs:
`/tmp/phase-a-baseline.log`, `/tmp/phase-a-after.log`.

| Configuration | Before median | After median | Before first edit | After first edit |
| --- | ---: | ---: | ---: | ---: |
| Debug | 85.16 ms | 85.05 ms | 225.06 ms | 233.12 ms |
| Release | 58.13 ms | 57.99 ms | 189.67 ms | 187.55 ms |

No material median regression was observed in this paired run. The Debug baseline
had a 538.46 ms outlier; after max was 233.12 ms. This is not evidence of an export-
related speedup. These are harness insert/layout/display-request timings, not
hardware key-to-screen latency or a guarantee of smooth typing.

## Actual manual observations

Generated disposable exports with the compiled Release exporter under
`/private/tmp/screenplay-fdx-export-audit`, then opened them in Final Draft 13.
The synthetic screenplay displayed proper scene heading, character, parenthetical,
dialogue and transition positioning; the selected action phrase rendered bold
and italic. The explicit break produced two script pages. Final Draft's Title
Page window displayed the six separate wording blocks, outside the script body.
The full Defenders export opened with a 15-page script count, matching the earlier
original-FDX observation. No original screenplay was edited or saved.

A separate local audit bundle used the compiled Release executable at `3506373`
and an isolated bundle identifier. No signing command or credential change was
needed. Created a new untitled document and typed a synthetic heading. File →
Export Final Draft FDX displayed the limitations review, then the native save
panel. Exported `UI-export.fdx` to the audit folder and parsed its XML afterward:
Scene Heading and `INT. EXPORT CHECK - DAY` were preserved. Quit the audit app.
The new disposable document autosaved as `Untitled_Screenplay 25.open-screenplay.json`
in Downloads. The installed app and notarized build remain unchanged.

## Remaining Phase A work

- Calibrate action-duration estimates and placeholder handling; retain honest ranges.
- Compare page counts with Final Draft on two additional scripts; propose the
  line-pitch/lock policy before changing it. Defenders remains 18 pages in the
  current ScreenplayOS layout versus 15 in Final Draft.
- Optional beat/scene targets with migration, Undo and plan-versus-estimate UI.
- Full phase acceptance, further live export review, and any distribution update.

Audio, takes and NLE round trip belong to later phases. No AI calls, credential
changes, signing changes, release publication or original-document edits occurred.
