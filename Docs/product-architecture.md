# ScreenplayOS Product Architecture

ScreenplayOS is a narrative suite that keeps the edit in mind from the first beat:
outline → script → shot list → boards → animatic → generation or shooting → edit.
It is built for professional teams working in AI-assisted film and TV, where writer,
director, and producer are often the same few people. Every stage carries timing
and editorial intent forward. The suite hands off to dedicated tools (NLEs,
generation services, DAWs) and reads their decisions back. It does not try to
replace them.

Edit-aware everywhere: expose planned versus estimated screen time and carry
consequences downstream. Hand off through open, standard formats with stable media
references. Imported editorial decisions are reviewable proposals, never silent
script mutations. Audio is first-class in an animatic. Correct screenplay output
remains mandatory; the connected pipeline is the product's distinguishing value.

Adopted 2026-10-08. The following capability inventory distinguishes current code
from the target product. Earlier future-tense descriptions remain design intent.
The package editor and legacy filmmaking document have different implemented
capabilities; no complete-project migration is implied.

ScreenplayOS is one film project represented through five synchronized views:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

The progression is:

**STORY → WORDS → COVERAGE → IMAGES → TIME**

These are not separate modules and they should not duplicate data. They are different professional work surfaces for the same underlying film.

The product is native professional filmmaking software with a local-first, multi-platform architecture. macOS is the reference professional workstation, while iPadOS, iOS, and Web should become platform-specific interfaces onto the same canonical project model.

The core interaction rule is:

**The view changes. The filmmaker's context does not.**

If the filmmaker is working on a scene, shot, or board, switching views should preserve that object wherever possible.

## Center Stage Model

| View | Center stage | Contextual area |
| --- | --- | --- |
| Outline | Story structure | Script Preview |
| Script | Screenplay | Navigator / Inspector |
| Shot | Shot structure | Shot Composer |
| Boards | Storyboard sequence | Board Details / variants |
| Edit | Viewer + timeline | Story Spine |

Each view must have one unmistakable creative focus. Secondary information should support that focus without taking over the workspace.

## Outline

Outline is the story-structure view.

The current implementation direction is correct: Outline center stage shows scene cards generated from the actual screenplay scenes. It is not a separate outline-only copy of the film.

Outline scene cards should support:

- selecting a scene
- previewing the scene in Script Preview
- opening the scene in Script
- adding scenes
- duplicating scenes
- deleting scenes
- moving scenes earlier or later
- eventually drag-and-drop reordering
- linking scenes to optional story-template beats

When a scene moves in Outline, the same scene range moves in Script and the Edit Spine follows the new order.

## Script

Script is the writing view.

The screenplay owns the workspace. It must remain an excellent professional screenwriting surface even if the filmmaker never uses Shot, Boards, or Edit.

Script should prioritize:

- screenplay formatting
- keyboard-first writing
- page behavior
- revision handling
- autocomplete
- find/replace
- notes and comments
- focus mode

Production, AI, and planning information may appear contextually, but they should not clutter the writing surface.

Script notes are canonical project annotations tied to screenplay elements and scene spine IDs. They should appear contextually across the five views without becoming a separate primary workspace.

## Shot

Shot is the coverage and camera-intent view.

Shot answers: **What do we intend to shoot or visualize?**

The primary object is the canonical shot. A shot can begin simply:

**14A - Wide - Mew walks across the beach.**

Shot Composer belongs here. It progressively exposes framing, camera, lens, movement, blocking, characters, location, notes, and related references. It should not become the Boards workspace.

## Boards

Boards is the visual sequence view.

Boards answers: **What does the scene look like, shot by shot?**

A board should reference a canonical shot whenever possible:

**Scene → Shot → Board**

The board image or visual placeholder should dominate each board card. Metadata stays subordinate.

Boards may come from manual drawing, imported images, reference imagery, AI image generation, previs frames, frame grabs, or later footage-derived frames. AI is one creation path, not the architecture.

## Boardomatic

Boardomatic is the first playable version of the film.

Until finished media exists, boards become temporary edit clips. Each board carries duration, and those durations create a playable storyboard sequence.

Boardomatic should grow toward:

- play and pause
- per-board duration
- scene playback
- sequence playback
- whole-film playback
- dialogue timing
- temp sound and music
- simple cuts
- playhead scrubbing

The central question is: **Does the movie play?**

The current implementation includes the first playable scene-level pass: play/pause, previous/next board, playhead scrubbing, active-board highlighting, and Edit viewer/timeline sync from the same selected board.

Boardomatic now feeds the edit spine. Board durations are synchronized into edit clips with stable shot, board, scene, script-source, timeline-start, and duration metadata.

## Edit

Edit is the time view.

Edit owns:

**Viewer + Timeline + Story Spine**

At first, the timeline is powered by Boardomatic clips. Later, those same timeline references can use richer media.

The current edit spine records clip-level timing instead of only scene markers. This is currently a generated post-production guide. Independent edit occurrences and media substitution that preserve editorial intent remain implementation work; source-kind enum values do not establish working media replacement. The target identity and storage contract is defined in project-format-decision.md.

The first post handoff export is an Edit Timeline CSV. It records one row per edit clip with seconds, 24 fps timecode, source type, scene identity, shot identity, board identity, and script-source references. This is intentionally simpler than a full NLE XML export, but it creates the data shape needed for that future step.

The media maturity path is:

**Board → Previs → Generated / filmed media → Final media**

The shot remains the stable creative object. The representation matures without forcing the filmmaker to rebuild the edit from scratch.

## Media Substitution

If Board 14B is already in the timeline and actual footage for Shot 14B later becomes available, the new media should replace the board while preserving as much editorial context as practical:

- shot identity
- timeline position
- scene relationship
- notes
- metadata
- approximate duration
- audio relationships where appropriate
- editorial markers

The real shot is not an unrelated imported clip. It is the next representation of the same planned shot.

## Data Model

The project should preserve stable identities:

```text
Project
  -> Sequence
  -> Scene
  -> Script content
  -> Shot
  -> Board(s)
  -> Media version(s)
  -> Edit instance(s)
```

One scene object should power Outline, Script, Shot, Boards, and Edit.

One shot object should remain identifiable across Shot, Boards, and Edit.

Boards and media should reference shots.

Edit instances should reference canonical objects rather than disconnected copies wherever practical.

## What Not To Add As Primary Views

Do not add peer-level modes for:

- Production
- Assets
- Characters
- Locations
- Schedule
- AI
- Storyboard Composer
- Media Library

Those capabilities can live in navigator, browser, contextual inspector, Shot Composer, Boards, Story Spine, command palette, or contextual overlays.

The primary mental model remains:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

## Pipeline stages and handoffs

Status is relative to the requested end-to-end pipeline, not a claim of external
application compatibility. Implemented means the named bounded behavior exists;
Partial means important parts of that stage are missing; Planned means no working
end-to-end implementation was found. Inventory inspected at `2ee74fd`.

| Stage | Status | Canonical data and timing signal | Current interchange; planned handoff | Evidence and remaining gap |
| --- | --- | --- | --- | --- |
| Outline | Partial | Story-template beats, scenes and stable source references; derived scene estimates | Native legacy document; target-duration fields and plan totals planned | `ScreenplayViewModel.swift` scene/story-template commands; `SceneSummaryTests.swift`, `EditorialIdentityTests.swift`. Beat and scene targets are not implemented. |
| Script | Partial | Elements, styles, title page, page layout; `SceneDurationEstimate` ranges | FDX import, reviewed DOCX/PDF/text import, PDF output; FDX export planned | `ScreenplayFDX/FDXImporter.swift`, `FDXImportTests.swift`, `PaginationTests.swift`, `PackagePrintTests.swift`. FDX export is absent; Defenders pagination differs from Final Draft. |
| Shot list | Partial | `Shot`, source references and setup/coverage intent | Native records and production reports; timed shot plan planned | `ScreenplayDomain/ScreenplayDocument.swift`, `EditorialIdentityTests.swift`. Ordered takes and explicit planned shot duration are not implemented. |
| Boards | Implemented (bounded board workflow) | `BoardFrame`, `BoardImageVersion`, duration and selection | Local image import/storage and explicit-consent generation; portable relative Board Images paths | `BoardImageStorage.swift`, `BoardImageAssistant.swift`, `BoardImageTests.swift`. This does not establish video takes or the proposed take migration. |
| Animatic | Partial | Timed boards and derived estimated scene segments, playhead and editorial order | Local board/placeholder playback, CSV and timing guides | `EditPlayback.swift`, `EditTimeLane.swift`, `ScenePlanningTimelineTests.swift`. Audio lanes, synchronized audiovisual playback, waveforms and scene looping remain acceptance work. |
| Generation or shooting | Planned (take workflow) | Proposed ordered takes, stable media references, provenance, selection, cost | Local video/still imports planned; existing board generation is a narrower feature | Existing `BoardImageVersion` is not a general take. Media-kind enum cases do not prove media decoding or substitution. No new generation integration is authorized for Phase C. |
| Edit handoff | Partial | Derived clips and independent scene-level editorial order; current 24 fps guide timing | CSV, Premiere EDL offline placeholders, FCPXML named gaps; media-linked OTIO and audio planned | `EditInterchange.swift`, `EditInterchangeTests.swift`, `ImportAndEditTests.swift`. Current EDL/FCPXML do not transfer linked media or audio; external NLE imports remain unverified. |
| Editorial round trip | Planned | Proposed imported edit decisions with source identity, timestamp and acceptance status | OTIO/FCPXML import and reviewable acceptance planned | No edited-timeline importer or transactional acceptance workflow exists. Changes must remain proposals until explicitly accepted, with Undo. |

### Phased implementation contract

Use the detailed [acceptance scenario](pipeline-acceptance-scenario.md). Implement
A (timing and interchange), B (audio), C (takes), then D (handoff and round trip),
with bounded commits and evidence notes. Extend canonical data only when its phase
needs it; do not introduce empty infrastructure for all phases at once.

Each new type requires encode/decode, unknown-field preservation, and legacy 0.1.3
migration tests. A reader rejecting unknown data and opening a protected copy is
not proof of lossless migration. Preserve source bytes and original identities;
version bumps require a tested migration. Large media remains outside canonical
JSON, addressed by stable IDs and portable relative paths. Board image versions
must migrate to takes without losing version history or metadata.

The planned fields are optional beat/scene targets; shot planned duration and
coverage type; ordered takes (kind, media, duration, in/out, candidate/selected/
rejected, selection note, local provenance/prompt, created time, rights notes,
optional cost and currency); audio items (kind, media, stable scene/shot/dialogue
anchor, offset, duration, gain and fades); and imported edit-decision proposals
(trim/reorder/removal/added clip, source file, timestamp, pending/accepted/rejected).
Prompt storage is local and does not grant permission to transmit it.
