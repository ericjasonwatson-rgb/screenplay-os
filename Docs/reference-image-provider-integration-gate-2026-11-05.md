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
