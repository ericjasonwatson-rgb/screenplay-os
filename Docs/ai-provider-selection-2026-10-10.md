# Provisional AI provider order — 2026-10-10

This decision records current implementation order, not permanent vendor preference.
Provider and model identifiers remain replaceable configuration behind capability
interfaces. The project owns the shot brief, script coverage, references, exact
request snapshot, result, revision history, cost and approval state.

## Production lessons received

- The previous production used many changing tools; the tool list itself is not a
  durable product requirement.
- The largest avoidable cost was re-editing weak or poorly directed generations.
- Review was a team screening followed by notes, revisions and approval.
- The central product gap is direction: many AI creators do not carry a coherent
  directorial decision from script to shot, board, boardomatic and edit.
- SAG voice performers, performance capture and historical characters belonged to
  that show. They do not justify prioritizing voice or likeness adapters now.

## Product test for every generation feature

A feature earns priority only if it reduces downstream editorial work. It must start
from a timed shot slot and a frozen director brief, use the relevant script coverage
and approved references, return revision-bound candidates to that same slot, and
support team notes, compare, approval and rejection. A generated asset that cannot
be traced to those decisions is a loose file and does not satisfy the product.

Measure success with first-pass acceptance, regenerations per approved shot, time
from request to approved take, continuity exceptions, and edit replacements after a
team screening. Raw generation count is not a success metric.

## Adapter order

1. **Text assist: OpenAI and Anthropic, retained.** Both are already implemented
   behind TextAssist. Keep user-selected model IDs. Text assists should next produce
   bounded shot-list and timing proposals with diffs; they must not rewrite a script.
2. **Board image: OpenAI first.** Use the existing adapter and evolve it toward
   reference-guided generation and precise edits. The current OpenAI Image API
   supports generation, edits, image inputs, flexible output options and separate
   quality-oriented and speed-oriented GPT Image models. For new quality-sensitive
   board work, prefer the quality-oriented model available to the user's account;
   do not overwrite a saved choice or assume access from documentation.
3. **Generated video: Runway first.** Its API exposes text-to-video and
   image-to-video as asynchronous tasks, accepts a board as the first-frame input,
   and can deliver H.264, ProRes or PNG-sequence outputs. That maps directly to the
   selected-board-to-timed-take workflow and professional editorial handoff.
4. **Video alternative: Google Veo after the first adapter.** Veo supports
   long-running video jobs and first/last-frame guidance in current Vertex AI
   documentation. Retain it as the first comparison adapter so provider routing is
   proven rather than merely abstracted.
5. **Voice, music, lip-sync and performance capture: deferred.** They remain valid
   capabilities, but they do not address the owner's current highest-cost failure.
   Voice work still requires the consent gate already specified in the architecture.

Runway is selected for the first video integration because its current API shape and
editorial output formats fit this product, not because it will always produce the
best image. ScreenplayOS must make provider comparison possible on the same frozen
shot brief before any later default changes.

## Implementation boundary

Do not add a live image or video send until AI-1 supplies durable jobs, exact request
preview, estimated-cost handling, activity history, cancellation and provenance.
AI-2 supplies the continuity bible and director-focused prompt composer before the
first production image/video workflow. Automated tests use MockProvider only.

Official contracts reviewed on 2026-10-10:

- https://developers.openai.com/api/docs/guides/image-generation/index.html
- https://developers.openai.com/api/reference/resources/images/methods/generate
- https://docs.dev.runwayml.com/guides/using-the-api/
- https://docs.dev.runwayml.com/guides/professional-outputs/
- https://docs.dev.runwayml.com/api-details/sdks/
- https://docs.cloud.google.com/vertex-ai/generative-ai/docs/video/generate-videos-from-first-and-last-frames
- https://platform.claude.com/docs/en/api/messages/create

Documentation establishes API shape, not account access, output quality, pricing
for a particular account or successful generation. Those require owner-run manual
evaluation with the same benchmark shot briefs.
