# Siri × production-image integration smoke — 2026-11-05

Status: isolated draft PR #8, stacked on production-image draft PR #5.
No changes are merged into main, and no paid generation is run by these tests.

## Scope and invariants

Bring Siri PR #3's read-only App Intents navigation into the image branch
as a smoke test. A Siri request stores only the symbolic workspace choice
(Outline, Script, Shot, Boards, Edit); it does not index or transmit script
text, board media, provider keys, job identifiers or billing settings.
The app consumes the pending request once and uses the existing
`ScreenplayViewModel.setWorkflowMode` command.

The cross-branch test modifies a local screenplay document to contain
an unselected generated-image Take and sends all five Siri requests
through the actual request/consume flow. It checks after each command:

- canonical screenplay document remains unchanged;
- selected board image is unchanged;
- board and shot durations and Take count are unchanged;
- the queued symbolic navigation action is consumed at most once.

## Test jobs

`Production Image Handoff` on this integration PR executes the
SiriWorkspace, ProductionImage, ProductionBoardApproval,
OpenAIReferenceImage and OpenAIProductionImage filters, plus the
preexisting full Swift package suite. A dedicated integration smoke
workflow is also committed for the integration branch.

## Fixture availability

Full editor regression tests depend on the exact files:

- `Tests/Fixtures/Defenders_of_Cat_Island.open-screenplay.json`
- `Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx`

Both expected paths returned NOT_FOUND on `main` and the
production-image branch. GitHub commit
`a0b19bfd96559263a46d1392945b13c8e7204966`, titled
"Remove private screenplay fixtures from public tree," explicitly
deleted those exact files. Respect the deliberate privacy boundary:
**do not restore private scripts to a public repository.** A pilot
PDF available in the user's Library is not equivalent to either
authored JSON or FDX source.

Public CI now uses SwiftPM's `--skip` option for the 12 precisely
identified tests requiring the private source files, logs a warning,
and runs the other tests without changes to their assertions. When
both originals are privately available, CI invokes the full suite
without skips. Do not call public-safe CI "all tests passed" or claim
private source-fidelity certification.

## Remaining gates

Full native-editor regression must be consistently green with the real
fixtures; Siri and production-image focused CI must pass on this
integration branch. Editorial OTIO/FilmCraft round-trip from draft
PR #1 must be validated independently before stacking its media
interchange code into an integration branch. Actual provider transport,
billing and manual Send remain outside automated tests.
