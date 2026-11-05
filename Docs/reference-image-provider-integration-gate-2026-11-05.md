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
