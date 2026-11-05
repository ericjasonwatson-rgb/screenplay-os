# Reference-image provider integration gate — 2026-11-05

**Status:** external dispatch intentionally disabled in this branch.

The existing `BoardImageAPI` calls `POST /v1/images/generations` with a JSON prompt only, and its `ImageGeneration` capability explicitly reports `acceptsReferenceImages = false`. It must **not** be reused to claim that an approved board image is being sent as a reference. A separate image-edit/reference adapter, using current documented provider-specific input types, is required.

The local preview's `providerID = local-preview-only` and `modelID = not-selected` are UI placeholders, not account/model claims. The preview validates approved board media and is not a dry-run of an actual provider payload.

## Conditions before real Send is enabled

1. Verify the provider's **specific** reference-image endpoint and supported model with its API documentation. Do not infer capability from a model name. Verify response parsing and PNG output by an opt-in paid integration test.
2. Implement `ReferenceImageGeneration` as a distinct interface from the current text-to-image one-PNG `ImageGeneration` contract. Pass a frozen typed request including exact raw image bytes (or an explicitly reviewed upload token) and prompt. Do not silently drop the reference image.
3. Present an exact provider-specific outgoing request preview (provider, model, prompt, every image, dimensions and known/unknown estimated charge), then acquire *separate* per-job send consent using the existing `GenerationJobController`. Approval of a board is not consent to send it.
4. Check `ProductionImageSendGate` at the point of user approval **and immediately before dispatch**; re-check stored image hash, approval revision and job fingerprint. Cancel if any value changes, the job is no longer at the expected consent state, or the model/provider selection differs.
5. Mark submitted only if the durable controller records consent and the request is ready to leave the machine. Ensure transient failures produce a reviewable error without changing board selection.
6. Decode and persist an immutable provider result, then use `ProductionImageTakeHandoff` to create an **unselected candidate**. No automatic image replacement, timeline retiming, or generation of video.
7. Verify pricing/account access separately and store observed costs, never report an unverified unknown cost as free. Run offline deterministic CI; a live paid provider test must be manually opted into and not part of PR CI.

The current `ProductionImageSendGate` is an *offline validation building block*. It neither mutates the durable job nor proves that a UI button was pressed. The calling UI and controller must enforce that connection. No production send implementation should use a boolean fabricated by a headless caller.

## Added dispatch preflight (2026-11-05)

`ProductionImageDispatchPreflight.prepare` combines a persisted queued job,
the exact previously consented request, the source approval revision, the
frozen image bytes and the provider-specific JSON builder. It blocks altered,
cancelled, unconsented and recovered queued jobs; recovered jobs must be
reviewed before any later submission. It does not attach credentials, call
URLSession, or mark a job submitted. The preflight result should be considered
ephemeral: any actual Send implementation must re-check it at dispatch time
and rely on the durable controller to record submission.

Next work: authenticated transport behind an explicitly user-triggered
command, safe response parsing and durable output storage, then candidate
Take creation and separate filmmaker adoption. Keep network tests opt-in.

## Added offline result validation and candidate storage

`OpenAIReferenceImageResponse.decode` accepts exactly one Base64 PNG
and rejects oversized bodies, remote URLs, malformed images and unsupported
response shapes. `ProductionImageResultPreparation.prepare` requires a
completed job record whose request, provider, model and board target match the
staged approval. It then writes immutable, hash-named local media using
`BoardImageStorage` and constructs an **unselected** generated-image `Take`.
This does not insert that Take into the canonical document or change the
selected board image. The calling service must still obtain the completed job
record from the persisted `GenerationJobController` rather than trusting an
unverified caller-provided record; the end-to-end integration test will verify
this link and adoption/Undo.

## Persistent job provenance gate (latest)

The production candidate path now exposes
`ProductionImageResultPreparation.prepareFromPersistedJob`. It reads a
validated terminal `GenerationJobRecord` directly from the existing durable
`GenerationJobController` actor before decoding or storing an output.
An unpersisted success record, awaiting-consent job, failed job or missing
job cannot create a candidate through this entrypoint. A successful test
runs the controller through stage, consent, submission and completion using
offline fixtures and verifies that the candidate remains unselected.

This still **does not** prove that an HTTP response belongs to a
particular provider request: a trusted transport must bind its response to
the exact submitted job and handle retries and provider errors. The returned
`Take` is not yet adopted into the canonical document or persisted as a
separate managed candidate. Implement that adoption through an undoable
shared command, not by silently replacing the selected storyboard.

## Canonical Boards candidate addition and Undo

`ProductionImageCandidateAdoption.appending` maps a validated `Take` to a
new `BoardImageVersion` on the existing `BoardFrame`, without changing
`selectedImageID`, shot IDs or duration. `ScreenplayViewModel.appendProductionImageCandidate`
checks the media is in the project's Board Images directory, verifies the
image's stored bytes and digest, records a document Undo snapshot, appends the
candidate to the canonical document and autosaves. The existing `TakeStrip`
projects these canonical versions and lets the filmmaker explicitly select
the candidate via `selectBoardImage`, a second undoable operation.

The underlying board remains authoritative and the Take sidecar continues to
be a derived projection. This avoids a competing take ledger being able to
silently change the edit. Tests cover non-selection, canonical encode/decode,
projected candidate status and two independent Undo/Redo steps.

Current release restriction: no live provider response handler invokes this
command. A future result handler must retrieve the succeeded job from the
persisted controller and use `prepareFromPersistedJob` before asking the
model to append the candidate.

## Injected transport lifecycle (offline; no live adapter)

`ProductionImageResponseExecution.execute` now accepts an injected
`ProductionImageResponseTransport`, performs the durable queued-job preflight,
marks the job submitted immediately before the single transport call, validates
the returned PNG before marking the job succeeded, then retrieves the persisted
success record to construct an unselected candidate Take. A rejected response
or provider error records a generic sanitized failure without exposing prompt,
media or API credentials. No retry is performed; attempts to reuse a completed
job fail through preflight. Tests exercise success, invalid response, transport
failure, and rejection of a second dispatch.

**Release blockers:** No live transport is registered in the app and this
executor is not attached to a Send button. A production transport must use
ephemeral URLSession, prohibit non-HTTPS redirects, cap response bytes before
allocation, add credentials only after explicit user action, and propagate
provider errors without leaking input. The UI must bind its Send button to the
same frozen review and durable consent record, handle cancellations and
recovered jobs carefully, then append the result through the existing undoable
model command. A succeeded provider job whose local candidate storage fails
needs a recoverable result-asset handoff rather than an automatic retry that
might create additional charges.

## Isolated opt-in OpenAI HTTPS transport

`OpenAIProductionImageTransport` implements the injected transport interface
but is **not instantiated by the app's Boards UI or any background agent**.
Its request builder pins `https://api.openai.com/v1/images/edits`, checks
the exact serialized payload SHA-256, refuses unknown endpoints, and appends
the bearer token only to an ephemeral outgoing HTTP request. The transport
uses an ephemeral URLSession with the existing redirect-rejection delegate,
disables cookies/cache, caps response bytes before buffering, checks task
cancellation, refuses non-200 responses and never persists raw provider
errors. Offline tests verify the origin, request body, absence of API tokens
from the body, tamper rejection and invalid destination rejection.

API contract checked against:
https://developers.openai.com/api/reference/resources/images/methods/edit
The documented JSON request accepts `images: [{ "image_url": "data:image/png;base64,..." }]`
plus `model` and `prompt`. Account access and model availability are not
implied by this documentation.

**Still disabled:** No user-facing Send button calls this adapter. A live
request requires explicit connection/consent, model verification, suitable
billing disclosure and an opt-in integration test. Responses are not assumed
to be billable at a known fixed amount.

## Boards UI: durable staging without send

`ProductionImagePlanningSheet` now offers **Stage OpenAI request for review
(no send)** after a revision-bound board approval and local brief have been
prepared. The new `ProductionImageJobStagingSheet` reads the current
approval sidecar, checks shot/board identity, restricts the media to the
project's own Board Images folder, verifies the selected image bytes through
`ApprovedProductionImageFlow`, and adds an awaiting-consent job to the
existing `GenerationJobController` via
`ProductionImageConsentCoordinator.stage`. The sheet displays the reference
image, exact prompt, model, provider, unknown-cost disclosure and saved job ID.
The user may cancel the staged job. Closing the sheet does not submit anything.

This is **not** a Send action or a paid generation integration. It deliberately
does not grant consent, advance the job to queued/running, or construct an
authenticated transport instance. An explicit per-job consent screen and
provider availability checks remain required before release. A job left
awaiting consent is inert; a user should be able to find/cancel it from the
generation activity interface before the live feature is launched.

## Separate consent review in Boards (2026-11-05)

The staged request now opens `ProductionImageConsentDecisionSheet`, which
displays the frozen approved image, exact text, provider/model, fingerprints,
and unknown-or-estimated cost. It requires an explicit acknowledgement of
future external transfer and potential charges. A user-initiated click on
**Authorize locally — queue only, no send** invokes the same
`ProductionImageConsentCoordinator.authorize` and durable
`GenerationJobController.grantConsent` as the offline regression tests.
The caller reloads the saved approval record and checks that it has not
changed before proceeding. No Send button or paid provider call is attached.

This local queue is deliberately inert. Leaving or reopening the screen
does not dispatch it. A production Send button will require a new,
single-action check of the job's queued state, selected reference, exact
payload and user intent before invoking `OpenAIProductionImageTransport`.
Queued jobs restored after relaunch also require explicit recovery review.

Outstanding UX: allow locating and cancelling saved awaiting-consent or
queued jobs after the review window is closed. Existing activity history
does not necessarily include unsent jobs; don't imply those are discoverable
there until a dedicated pending-job view is provided.

## Durable consent and pending-job recovery UI

The Boards staging sheet now presents a distinct `ProductionImageConsentDecisionSheet`
with the exact saved prompt, selected image, provider, model and cost
disclosure. The acknowledgement control is initially unchecked. The
filmmaker may explicitly **Authorize locally — queue only, no send**.
Before calling the durable controller, the UI reloads the local
approval record, checks that it matches the staged approval, and
the coordinator revalidates the live shot, board and stored job.
This action creates an inert queued job, not a transmission.

`ProductionImagePendingJobsSheet` lists awaiting-consent and queued
production-image jobs from the project's durable ledger, including
jobs left by earlier sessions. Each can be cancelled without any
provider request. A smoke test checks that rendering the view never
mutates the screenplay; a recovery test verifies that staged jobs
persist across controller reinitialization and are cancellable.

The release still needs a deliberately named **Send now** action,
a dedicated final confirmation with cost/access checks, the live
adapter dispatch, robust cancellation/failure recovery and a real
opt-in provider test. None is enabled by local queue authorization.

## Explicit final Send action (development branch only)

The Boards staging sheet now has a separate **Review and Send now…**
action that becomes available only after local queue consent. The final
`ProductionImageSendConfirmationSheet` displays the exact reference
image, prompt, request hash, provider/model and unknown-cost warning,
and requires a fresh unchecked acknowledgement before the filmmaker can
press **Send now (may incur charges)**. Rendering the screen cannot
submit a request.

The click handler reloads the saved board approval, checks current
project identity, uses the app's existing AI-generation entitlement,
loads the OpenAI credential from Keychain only at dispatch, invokes
`ProductionImageResponseExecution` through the authenticated
`OpenAIProductionImageTransport`, and appends the verified result
as an unselected canonical Board Take only if the project/shot/board
still match. Provider errors are not shown raw. A failed or potentially
billable request is not automatically retried.

**Not yet release-certified:** live API credentials/account/model
capabilities, actual provider response compatibility, pricing, retry
and cancellation outcomes, and recovery of an output if local
candidate storage fails after the provider job is marked succeeded.
Never claim these behaviors are verified solely from offline CI. A
live paid integration test requires an intentional user Send click.
This work remains unmerged and is not an instruction to run such
a test during development.

## Completed-image recovery in the Boards request manager

The **Production Image Jobs & Recovery** screen now shows both unsent
requests and previously completed image jobs whose local output vault is
readable but whose generated Take has not yet been added to the canonical
board. The filmmaker can select **Restore as unselected Take (no send)**.
This uses `ProductionImageCompletedResultRecovery`, reloads the job and
approval from durable storage, checks the current board/shot/revision and
local saved PNG, then adds a new canonical image version only if the
project remains unchanged. It performs no authenticated request, does
not automatically select the new version and preserves edit timing.

A changed or missing approval blocks automatic adoption, leaving the
previously paid PNG in the local vault for manual recovery. The screen
never offers a new paid generation as the recovery action. Media
restoration is separate from the project's portable export and should
be covered by a later project-package migration.

## Interrupted completion: saved image, unfinished job ledger

`ProductionImageInterruptedCompletionRecovery.completeFromVault` reconciles
the case where a provider response was validated and stored in the private
job-specific result vault, but saving `status=succeeded` to the generation
ledger failed or the app exited. The original job remains `running`.
The filmmaker may now choose **Reconcile saved output and restore (no send)**
from the production-image job manager. The operation verifies that the job
was submitted, that a real locally saved PNG exists, and that the approval,
reference image, prompt revision, shot and board still match. Only then
does it persist `succeeded` and call the existing offline candidate
recovery. It never invokes network transport or retries paid generation.

Queued jobs without submission and running jobs without a preserved result
cannot be marked successful by this operation. A changed approval blocks
automatic insertion. The result remains unselected until the user chooses
it in Boards. Mac CI now invokes previously omitted BoardApproval and OpenAI
reference-image suites as well as the ProductionImage suites.

Known limitation: an ambiguous in-flight provider request with **no
recoverable local output** still needs an explicit reconciliation design;
it must not be automatically retried. End-to-end real-provider testing is
not part of this change.
