# ScreenplayOS shared integration contract — 2026-11-05

Status: proposed technical contract; implementation is incremental and unmerged.

## One creative authority

ScreenplayOS owns the canonical ProjectID, screenplay/scene and shot UUIDs, authored boards, selected board image, shot timing and editorial occurrences. A UI button, Siri action, and external provider must not each implement their own mutations; eventually all will invoke the same tested, undoable application command.

### Dependency sequence

1. Stabilize Mac builds and project persistence. PR #1 has the media interchange proposal, and its full native UI regression suite is not green. No merge.
2. Approve a selected storyboard in the project UI. PR #4 currently models approval as a caller-supplied set, not a persistent approval workflow.
3. Generate a revision-bound production-image brief locally. No network request or raw image transfer.
4. Display an exact outgoing payload preview, including any board image/reference bytes, provider/model, charge/unknown charge, consent, and revisions. A provider must explicitly support reference-image input; the old OpenAI one-PNG text-only adapter does not.
5. Only after user-authorized generation and robust output decoding, save immutable media and create a candidate Take with unchanged shot/board identity and provenance. The stacked PR adds a pure mapping, not a working generation pipeline.
6. Require explicit adoption via a shared undoable command. Do not overwrite the approved storyboard or rewrite a timeline by selecting a candidate.
7. Video generation and editorial handoff inherit the same shot/take identities, with reviewable external edits.
8. Siri/App Intents call only verified application commands. Current PR #3 provides read-only navigation; no creative Siri actions yet.

## Cross-branch contracts

| Producer | Output | Consumer | Safety |
| --- | --- | --- | --- |
| Board authoring | stable shotID/boardID/selected image version, duration | ProductionImagePlanning | board-specific approval and stale check |
| ProductionImagePlanning | immutable brief with exact SHA-256 prompt snapshot and local references | consent/request UI (future) | review and explicit send; no implicit network |
| Image adapter | decoded and hash-verified local image, job and provider metadata | ProductionImageTakeHandoff | validates current board and produces candidate only |
| Take ledger | candidate media version, immutable asset identity | Boards / Edit (future) | selection/adoption transactional and undoable |
| Editorial interchange | scene, shot, take and edit occurrence identities | external NLE (future) | compare proposal, not silent import |
| Siri Intent | narrow symbolic user request | shared command layer (future) | no direct document mutation or content indexing |

## Tests and remaining acceptance gates

Existing focused CI reported success for PR #3 Siri navigation and PR #4 board planning on 2026-11-05. This stacked branch adds candidate-handoff tests but does not establish merged compatibility. Native macOS editor tests in PR #1 still had failures.

End-to-end must use a Defenders of Cat Island fixture: approve board, prepare brief, explicitly authorize fixed request, generate deterministic fixture via mock, decode and persist media, add candidate take, choose it with Undo, update Boardomatic without changing timing, export OTIO, re-import review proposals, and verify all IDs and provenance. Also test interrupted writes, missing files, stale result, revoked consent, and offline operation. No vendor payments or accounts in CI.

Do not label a mock signature-only buffer as a valid PNG. The pure handoff's byte signature is a coarse guard; the caller MUST use the real image decoder and durable file store before passing the bytes.

## Regression gate refresh — 2026-11-05

The production-image branch now runs a full macOS Swift package test job
alongside the focused ProductionImage, ProductionBoardApproval and OpenAI
reference-image request suites. This is a **pre-merge verification** of
shared model behavior, not a claim that PR #1, #3, #4 or #5 have merged.

Image generation now uses a persistent job state and a local result vault;
the user-facing final Send action remains explicitly gated and no network
calls are made during CI. Real request completion timestamps are recorded
when the provider response has actually arrived and been stored, rather
than estimating a fixed latency. Ambiguous transport failures are not
automatically retried.

Cross-branch acceptance is still needed for:
- canonical board and Take projection, selection/Undo and editorial timing;
- OTIO interchange and import review with stable shot/take IDs;
- Siri/App Intent navigation against the resulting shared project schema;
- end-to-end application packaging and manual live-provider authorization.

Do not merge stacked PR #5 directly into main: review and merge its base
PR #4 or rebase deliberately after the full regression status is known.

## Full regression results and integration blockers

The first full macOS run on the image branch surfaced three existing
native-editor UI failures unrelated to the image contract:
`NativeEditorTests.fitWidthTracksPanelsWithoutChangingScriptOrSelection`,
`NativeEditorTests.titleEditorPreviewUpdatesAndRecoversFromOverflow`, and
`ChromeObservationTests.windowChangesModesAndReturnsToCurrentText`.
These failures were already noted in the native-editor stabilization
workstream and must be addressed and reverified before merging the
editorial branch. The same run exposed a stale test assertion on the
new uncertain-transport status; this has been corrected to expect a
persisted `running` job (not `failed`) when the provider outcome
cannot be established. A new CI run will determine whether the focused
image suite is clean after that correction.

Do not relax or delete native rendering tests solely to achieve a green
badge. Investigate runtime view lifecycle, zoom state and title overflow
on macOS, then repeat the full suite. Avoid merging any of the stacked
branches until the cross-branch acceptance gates pass.

## Native editor stabilization follow-up

Full suite run #118 isolated three native view lifecycle/rendering failures:
fit-width zoom after hiding and restoring panels, title preview after
overflow, and workspace mode transition retaining an outgoing writing
view. A separate 60-second recovery-test timeout has occurred when the
full suite is highly contended on the shared macOS main actor; it needs
dedicated repetition before attributing the timeout to the feature.

Follow-up commits make title-PDF rendering revision-bound: old PDF
canvases are no longer eligible for display after the title source
changes. Structural workflow switches now refresh scoped Chrome signals
synchronously so the old native editor can leave the view hierarchy
before the new workspace is laid out. These are intended narrow fixes;
their effectiveness must be established by the newly queued full suite,
not inferred from a successful code commit.

The fit-width round-trip case remains open pending its independent
macOS result and diagnosis of split-view width restoration. Preserve
the no-mutation and selection invariants in NativeEditorTests.
