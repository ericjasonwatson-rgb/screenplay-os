ScreenplayOS: AI-native production direction

PRECONDITIONS
- Finish the stabilization task first: Scripts/test.sh passes in Debug and Release, and main plus the tag
  v0.1.3-build26-source are pushed.
- This direction SUPERSEDES the phase order in the earlier "product direction and next build phases" prompt.
  Keep that prompt's Phase A (FDX export, honest duration estimates, line-pitch decision, target durations):
  AI output built on wrong timing is worthless. Then follow the AI phases below.
- Docs/storykit-architecture-proposal.md stays ON HOLD. Do not implement it or depend on it.

READ FIRST
AGENTS.md and its listed docs, Docs/free-core-open-projects-amendment.md (AI and egress rules),
Docs/dialogue-assistant.md, Docs/ai-board-images.md, Sources/ScreenplayOSApp/DialogueProvider.swift,
DialogueAssistant.swift, BoardImageAssistant.swift, BoardImageStorage.swift, and the AuditFixTests.

1. PRODUCT DIRECTION (governing statement)
ScreenplayOS is a production system for AI-native filmmaking. It grew out of producing a fully AI-assisted
series, and it is built for the way film, series, and animation are now made. Writing, planning, generation,
and the edit live in one connected project: outline → script → shots → continuity bible → generation →
takes → timed animatic with audio → handoff to the edit. AI is first-class throughout, but always:
- grounded in the project: prompts are composed from the script, the shot, and the continuity bible,
  never from a blank box;
- consented: nothing leaves the Mac without an explicit, previewed send;
- provider-agnostic: the best model changes monthly, so the app routes work rather than locking in;
- accountable: every generated asset records its source, prompt, cost, and rights;
- human-directed: AI proposes, the user adopts, and adoption is undoable.
The edit-aware principle holds: every generation lands in a timed shot slot, not a loose folder.
The free core holds: writing, outlining, shots, boards from local files, and export work offline with no account.

Lessons from production (OWNER: fill in from On This Day… 1776 before running this prompt):
- Generation tools actually used (image, video, voice, music, upscaling, lip-sync): [LIST]
- Biggest time and money sinks: [e.g. character drift, regenerating for continuity, tracking versions, approvals]
- Approval and review path with the client: [DESCRIBE]
- Rights and compliance needs (performer consent, voice and likeness, disclosure): [DESCRIBE]
Use this list to choose the first provider adapters and to order features within each phase.
If it is still blank, stop after Phase AI-0 and ask the owner.

2. GOVERNANCE CHANGES (docs only, one commit, before code)
- AGENTS.md: put the direction statement above first. Replace "Writing-first priority … writing wins" with
  this ranking: protect work and data; consent and provenance for anything sent to or received from AI;
  correct screenplay output and interchange (PDF, FDX); edit-aware continuity from script to generation
  to edit; readability; polish.
  Replace the AI sentence in the free-core paragraph with: "AI features are first-class but optional.
  Creative-content egress requires an explicit, previewed send per request or per batch. Results are
  revision-bound, adopted explicitly, and undoable. Ordinary analytics never transmit screenplay text,
  prompts, or media."
- Add Docs/ai-production-architecture.md covering the provider layer, job model, continuity bible,
  prompt composer, takes, cost ledger, provenance, consent, and the mapping from each script/shot object
  to its AI inputs and outputs. Mark each part Implemented / Partial / Planned with evidence.
- Do not claim provider support, model names, or capabilities that aren't implemented and tested.

3. ARCHITECTURE (bounded, incremental; extend the existing code, don't rewrite it)
A. Provider layer
   - A Swift protocol per capability: TextAssist, ImageGeneration, VideoGeneration, VoiceGeneration
     (TTS and voice-to-voice), and later MusicGeneration. Each adapter declares its capabilities, limits
     (resolutions, durations, aspect ratios, reference-image support), and pricing hints.
   - Generalize the existing OpenAI and Anthropic code into adapters. Keep the existing behavior:
     redirects rejected, ephemeral sessions, Keychain storage, sanitized errors, no keys in logs.
   - Model IDs are user-selectable, fetched from the provider's model-list endpoint where one exists,
     and persisted. Never hardcode a model as the only option. (The current default
     "gpt-image-2.5-flare" is unverified; replace it with a fetched list or a clearly editable field.)
   - Before writing an adapter, verify each provider's current official API docs, and record the doc URL
     and verification date in a comment. No guessing at endpoints.
   - Ship first: a deterministic MockProvider for every capability (used by all tests and demos), plus the
     owner's first two providers from the 1776 list. Add more only after the job model is proven.
   - Optional later: local models (e.g. Core ML or local servers) with the same protocol, so egress becomes zero.
B. Generation jobs
   - Job model: id, capability, provider and model, a composed-prompt snapshot, reference assets,
     parameters, the target object (shot / board / dialogue line / scene), project revision at submit,
     and status (draft | awaiting consent | queued | running | succeeded | failed | cancelled).
     Also: estimated and actual cost, timestamps, and an error.
   - A queue that runs off the main thread, with concurrency limits per provider, polling for async video
     jobs, resuming after relaunch (persisted locally), cancellation, and retry only on user request.
   - Results land as Takes on the target shot (see D), never loose. Stale results (the project revision
     changed in a way that affects the target) are flagged, not silently applied.
C. Continuity bible (the core differentiator)
   - Project-level entries for Characters, Locations, Props, and Style. Each has a name, description,
     canonical reference images (local files), visual and voice notes, negative constraints, and
     per-provider extras (e.g. character IDs or seeds if supported).
   - Automatic links: character cues and scene headings in the script resolve to bible entries
     (with a suggest-and-confirm step for new names). Shots inherit their scene's characters and location.
   - Consent and rights per character entry: real performer? consent on file? voice clone allowed?
     likeness allowed? notes and an expiry. Generation that uses a likeness or voice without recorded
     consent is blocked with a clear message.
D. Prompt composer
   - Builds a generation prompt from: the shot description and type, the covered script lines, scene
     heading, time of day, characters and location from the bible, the style entry, shot duration,
     and aspect ratio.
   - Shows the composed prompt and attached references in an editable preview. What is sent is exactly
     what was previewed (snapshot stored on the job).
   - Templates per capability and per provider, editable per project, and versioned.
E. Takes, selection, review
   - Take: kind (board still | generated image | generated video | filmed clip | voice), media file
     (in a project media folder with relative paths, content-hashed like Board Images), duration,
     in and out points, status (candidate | selected | rejected), a note, and its job link.
   - Migrate existing BoardImageVersion data into Takes without loss (with a tested migration).
   - Shot view: a take strip with compare-two mode and keyboard selection. The animatic plays the
     selected take in each slot, falling back to the board.
   - Review status per shot (draft | needs review | approved), with a reviewer note, for client and
     director approvals. A local review export (an HTML contact sheet or PDF of selected takes with notes)
     needs no server.
F. Cost ledger and budgets
   - Every job records estimated (before send) and actual cost when the provider reports it,
     otherwise estimated only and marked as such.
   - Totals per scene, sequence, provider, and project. An optional budget per project or sequence
     with a warning before a send would exceed it.
   - A cost report export (CSV) for producers.
G. Provenance
   - Every take stores: provider, model, version, job id, prompt snapshot hash (and the full prompt locally),
     reference assets used, consent records relied on, the user who adopted it, and timestamps.
   - Exports carry provenance: sidecar JSON next to media, and metadata in OTIO/FCPXML clip notes
     where supported.
   - Design for C2PA/Content Credentials compatibility (store what's needed); implement signing later.
   - A per-project "AI disclosure" report: which shots, models, and performers were used.
H. Script-aware assists (text; all with preview, explicit send, revision binding, and undoable adoption)
   - Existing: dialogue alternatives. Keep its consent pattern as the template for all assists.
   - Add: shot-list suggestions for a scene (coverage proposals with durations) that adopt into the shot list;
     board prompt drafting from the composer; beat-to-scene outline suggestions; and scene timing
     sanity checks.
   - Never rewrite the screenplay wholesale. Proposals target specific elements and show diffs.
I. Audio with AI
   - Audio lanes in the animatic (temp VO, music, effects), as in the earlier direction prompt.
   - Generate temp VO per dialogue line through a VoiceGeneration adapter, using the bible's voice entry.
     Consent rules apply. Generated VO is a Take on the dialogue line and lands in the temp-VO lane,
     timed to its shot.
J. Handoff
   - OpenTimelineIO export with video and audio lanes, selected takes, relative media paths, and clip
     names and metadata keyed to scene, shot, and take IDs plus provenance.
   - Keep the Final Cut XML and Premiere EDL exports working.
   - Round-trip import of edited OTIO/FCPXML as reviewable proposals (from the earlier direction prompt).

4. PRIVACY AND SAFETY RULES (non-negotiable)
- No AI call happens without a user action and a visible preview of exactly what will be sent
  (text, images, audio), the provider, the model, and the estimated cost. A batch send previews the batch.
- Keys live only in the Keychain. Read them off the main thread. Never log or display them, and redact
  them from provider errors (cover sk-*, sk-ant-*, bearer tokens, and fragments of prompts).
- No telemetry. A local, user-visible activity log of every send (what, where, when, cost) that
  the user can export.
- Tests and CI never call real providers. MockProvider only. No live keys in the repo, tests, or fixtures.
- Consent records gate likeness and voice generation. Missing consent blocks the job; it never just warns.
- Free core: with no keys and no network, every non-AI feature works and the AI UI explains what's needed
  instead of failing.

5. PHASES (each phase: small commits, tests, a Docs/ note with evidence, typing-performance benchmark unchanged)
AI-0  Governance changes and docs; architecture doc; MockProvider; the provider protocol with
      the existing OpenAI/Anthropic code moved behind it (no behavior change; existing tests pass).
AI-1  Jobs, queue, consent preview, cost ledger, provenance records, and the activity log.
      Migrate board image versions to Takes.
AI-2  Continuity bible with script linking and consent records; the prompt composer with editable preview.
AI-3  Image generation into Takes for shots (via the first real image adapter from the 1776 list);
      take strip, selection, and the animatic using selected takes; review status and contact-sheet export.
AI-4  Video generation (async jobs) into Takes, plus the first real video adapter from the 1776 list.
AI-5  Audio lanes and voice generation for temp VO with consent gating.
AI-6  OTIO handoff with provenance metadata; edit round-trip proposals; the AI disclosure report.
Throughout: the script-aware assists in section H, one at a time, each with the dialogue-assistant
consent pattern.

6. ACCEPTANCE SCENARIO (automated with MockProvider, plus a manual checklist with real providers
   run by the owner)
A two-minute, three-scene sequence:
 a. Outline with target durations; script written; estimates shown against targets.
 b. Bible: two characters (one marked as a real performer with recorded consent, one fictional),
    one location, one style. Script cues link to the characters automatically.
 c. Shot-list assist proposes coverage; the user adopts part of it, and undo works.
 d. For each shot, the composer builds a prompt from the script and bible. The preview shows exactly what
    will be sent and the estimated cost. A batch of 12 image jobs runs off the main thread and can be
    cancelled midway; results land as Takes in the right shots.
 e. The user selects takes and the animatic plays them, timed. Two shots get video takes via async jobs
    that survive an app relaunch.
 f. Temp VO is generated for each dialogue line (the consented performer allowed; a test with consent
    removed is blocked) and lands in the VO lane in sync.
 g. The cost report matches the sum of the jobs; the budget warning fires when exceeded.
 h. OTIO export opens in Resolve or Premiere with the selected takes and VO in order, and with provenance
    sidecars present.
 i. An edited OTIO comes back; the trims and reorder appear as proposals; accepting updates shots
    and the outline; undo reverts.
 j. With networking disabled and no keys, everything except generation still works.
 k. No screenplay text, prompt, or media appears in any network request except an explicit send
    (verify with a network-recording test harness against MockProvider).

7. DELIVERABLE FOR EACH PHASE
What changed (file:line), tests added and pass counts, performance numbers, manual checks actually
performed with observations, and what remains. Keep automated checks, observations, and unverified
assumptions in separate sections. List any provider documentation you relied on, with dates.