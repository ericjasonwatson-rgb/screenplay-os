# AI-native production architecture

Adopted 2026-10-10. Governing request: [preserved direction](ai-native-production-direction.md).
This is an implementation inventory and bounded contract, not a declaration that
future generation capabilities ship. Baseline inspected: `9199ee0`.

## Gates and phase order

Stabilization requires Debug and Release `Scripts/test.sh` and verified remote
main plus `v0.1.3-build26-source`. Retain Phase A: FDX export, honest duration
ranges, a lock-preserving line-pitch decision, and separate target durations.
FDX export and legacy targets exist. The line-pitch decision retains legacy as
production and keeps experimental pagination disabled pending two independent
rendered comparisons. Those comparisons rejected candidate promotion; Phase A is
accepted with legacy pagination and no compatibility claim.
See phase-a-fdx-export.md, phase-a-duration-targets.md and
pagination-comparison-2026-10-08.md. Do not infer full Phase A acceptance from
passing tests. AI-1 may now proceed; production generation still waits for its job,
preview, provenance and activity-history gates.

The owner supplied the production lessons on 2026-10-10. The expensive failure
mode was generation that created extensive downstream re-editing. Review happened
through team screenings and feedback. The product therefore optimizes for directed,
revision-aware generation from script through shots, boards, boardomatic and edit,
not for a large catalog of disconnected generation buttons. Voice performers,
performance capture and historical-character likeness were specific to the prior
show and do not set the first adapter order. See ai-provider-selection-2026-10-10.md.
Storykit remains ON HOLD. No storage migration is authorized by this inventory.

## Evidence inventory

| Component | Status at baseline | Evidence and precise gap |
| --- | --- | --- |
| Provider layer | Partial | DialogueProvider.swift has OpenAI Responses and Anthropic Messages, explicit model listing and editable persisted IDs. BoardImageAssistant.swift has OpenAI image generation and an editable persisted model. No capability protocols or mock provider yet. |
| Job model and queue | Planned | DialogueConnection and BoardImageAssistant have transient Task/cancellation tokens, not durable jobs. No relaunch resume, concurrency limits, polling, retry queue or ledger. |
| Continuity bible | Planned | Character cues and scene headings exist; there is no canonical character/location/prop/style reference library or performer-consent store. |
| Prompt composer | Partial | DialogueSnapshot.capture and BoardGenerationSnapshot.prompt compose scene-grounded text. No attached references, bible resolution, templates, cost preview or exact complete-request preview. |
| Takes and review | Partial | BoardImageVersion stores id, fileURL, SHA-256, prompt and model; selectedImageID selects a version. No general video/voice Take, in/out points, review status or compare-two workflow. |
| Cost ledger and budgets | Planned | API-charge notices are present; no estimated/actual amounts, budgets, totals or CSV cost report. Unknown price must not be shown as zero. |
| Provenance | Partial | Board version prompt/model/hash exist. No durable job, provider/version, consent references, adopter identity, complete timestamps, export sidecars or disclosure report. |
| Consent and adoption | Partial | Explicit send and snapshot-current checks; dialogue insertion/replacement and board adoption are undoable. No likeness/voice consent gate or batch preview. |
| Local media | Implemented (boards only) | BoardImageStorage validates PNG/hash, content-addresses files, rejects path/symlink escapes, gathers portable relative board references. AuditFixTests covers relocation. No general media migration. |
| Audio / video generation | Planned | No real adapter, take playback pipeline or VO lane. Protocols and mocks alone cannot establish support. |
| Handoff | Partial | EditInterchange.swift exports EDL offline placeholders/FCPXML gaps, not selected media with audio. OTIO and reviewable edited-timeline import are planned. |
| Free core | Implemented (bounded existing features) | Non-AI authoring does not call DialogueAPI or BoardImageAPI. No account gate for local writing, shots, local boards or supported export. Full offline acceptance scenario remains future work. |

## Service boundary and object mapping

Provider protocols belong in the service layer, outside canonical ScreenplayDomain.
Each adapter advertises only its implemented capability and local constraints;
account/model limits and price remain unknown unless verified. Models remain
user-selected. Credentials stay ephemeral in requests and persist only in Keychain.
Existing request serialization, response validation, ephemeral sessions and redirect
rejection remain the transport contract during AI-0; new protocols must not bypass it.

| Target | Existing identity/input binding | Result/adoption | Planned extension |
| --- | --- | --- | --- |
| Dialogue | screenplay UUID, element UUID, element snapshot, scene excerpt | Three transient alternatives; insert/replace via existing Undo | Text job linked to line and revision; diff, costs and provenance |
| Shot/board | document UUID, Shot UUID, sceneSpineID, elements, related boards and target board UUID | Validated PNG becomes explicit board version | Job → candidate Take → selected Take; stable timed shot slot |
| Scene/outline | scene spine/source elements and optional targets | No network assist currently | Coverage/beat/timing proposals adopted selectively, undoably |
| Character/location/prop/style | No bible IDs currently | None | Confirmed script-to-bible links; local references, rights and expiry |
| Voice | Dialogue/shot linkage not implemented for audio | None | Consented voice Take → temp VO lane, revision-bound timing |

AI-1 introduces versioned local job records: identity, capability, provider/model,
previewed input snapshot and references, parameters, target/revision, status,
estimated/actual cost, timestamps and sanitized error. Queue states are draft,
awaiting consent, queued, running, succeeded, failed and cancelled. No automatic
retry; relaunch must not re-send an ambiguous paid request. Pending results remain
candidates; changed target inputs make them stale. Durable provider polling IDs
are not canonical shot identity. Store no credentials in a job or export.

A later Take contains media kind, relative content-hashed media reference,
duration/in/out, candidate/selected/rejected status, note and job/provenance link.
BoardImageVersion migration must preserve UUIDs, all versions, selection, hashes,
prompts, models, paths, durations and unknown metadata with tested rollback.
Never delete source media or assume legacy/package document parity.

AI-2 adds bible entries and prompt composition. Real-performer voice/likeness
requests fail closed without applicable unexpired consent. The preview must show
exact text, all attached media, recipient/model and estimated cost (or explicit
unavailability), and freeze those bytes at Send. A batch requires batch consent.
No screenplay rewrite, implicit typing-triggered egress or telemetry is permitted.

AI-3–6 add real image/video/voice adapters, take selection and review, audio lanes,
OTIO plus provenance sidecars and reviewable round-trip proposals, in that order.
Keep EDL/FCPXML behavior intact. C2PA compatibility is a metadata design target;
Content Credentials signing is not implemented. Use the full two-minute scenario
in the preserved brief; passing mocks cannot prove NLE or provider interoperability.

## Known privacy gaps to resolve before new production sends

- DialogueConnection and board generation read Keychain from MainActor tasks.
  Move reads off the UI thread with cancellation/late-result tests.
- Image errors redact full key/prompt and sk-prefixed keys, but may retain prompt
  fragments or bearer tokens in provider messages. Do not call this complete redaction.
- Preview currently omits some fixed transport/system parameters and cost. Preserve
  behavior in AI-0, then make the complete frozen request visible in AI-1.
- No durable, user-exportable send activity log exists.
- No automated network-recording proof of the full acceptance scenario exists.

These are tracked gaps, not permissions to send additional content or ship unsafe
new capabilities. Automated work uses mocks/fixtures and never credentials.

## AI-0 interface increment — 2026-10-10

The baseline table above is retained as the before-state. Provider abstraction is
now **Implemented (bounded)** in AIProviderCapabilities.swift: TextAssist,
ImageGeneration, VideoGeneration and VoiceGeneration are separate Sendable
service protocols. DialogueTextAdapter binds the existing transport to either
OpenAI or Anthropic; BoardImageAPI conforms to ImageGeneration. DialogueConnection
accepts an adapter factory and BoardImageAssistant accepts an image provider.
Existing live request serialization, Keychain operations, response/error handling,
selected model storage, cancellation tokens and adoption checks are unchanged.

MockProvider implements all four interfaces without network, Keychain, disk access,
clock or random identity. Its explicit byte fixtures test service routing, not
media decoding. Missing video/voice fixtures fail; no fake file is advertised as
playable footage. Mocks are injectable and absent from the production provider
picker. Async video polling/resumption belongs to AI-1/AI-4, not these interfaces.
MusicGeneration remains deferred. No schema or canonical document changes occur.

Metadata reports implemented adapter limits only: current image output is one
1536x1024 PNG without reference-image input; text remains the existing three-line
assist. Price is unknown (nil), not zero; future per-model duration/aspect/reference
constraints must come from verified adapters. The media request is an ephemeral
mock boundary, not the future serialized job format.

The image model remains an editable, persisted field. Official documentation now
lists gpt-image-2.5-flare; documentation does not prove a user's account access or
successful generation. This phase does not replace the user's saved selection or
claim model discovery for image capabilities.

Official contracts opened on 2026-10-10 (no authenticated/provider generation calls):
- https://developers.openai.com/api/docs/guides/text
- https://developers.openai.com/api/reference/resources/models/methods/list
- https://developers.openai.com/api/reference/go/resources/images/methods/generate
- https://platform.claude.com/docs/en/api/messages/create
- https://platform.claude.com/docs/en/api/models/list

See ai-0-validation.md for exact test counts, performance and remaining gates.

## AI-1 durable-record increment — 2026-10-10

GenerationJob.swift now implements the versioned project-bound job record, exact
request snapshot/hash, relative reference metadata, integer-micro cost records,
strict state validation and a local atomic JSON sidecar store. The sidecar is not
part of legacy screenplay JSON or the draft open-package schema, and no app path
installs it yet. No queue, relaunch reconciliation, consent UI, activity export,
Take migration or live provider send is claimed. See
ai-1-generation-job-foundation.md for evidence and the next bounded increment.
