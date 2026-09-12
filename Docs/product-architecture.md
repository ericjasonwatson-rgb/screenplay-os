# ScreenplayOS Product Architecture

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

The current edit spine records clip-level timing instead of only scene markers. This gives the project a replaceable post-production guide: a board placeholder can become generated video or production media while keeping the same scene, shot, source, and timeline position.

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
