# Master UI / UX Design Constitution

## One Film. Five Focused Views.

ScreenplayOS is a serious professional filmmaking instrument.

It is not a conventional SaaS product, production-management dashboard, AI wrapper, or collection of loosely connected filmmaking tools.

The application is built around one fundamental idea:

**One film project can be experienced through multiple specialized representations.**

The five primary views are:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

They correspond to five different modes of filmmaking thought:

- **Outline = Story**
- **Script = Words**
- **Shot = Coverage / Camera Intent**
- **Boards = Images**
- **Edit = Time**

The progression is:

**Story → Words → Shots → Images → Time**

These are not separate modules, files, or stages requiring export/import. They are five focused views into the same underlying film project.

## The Ableton Principle

Ableton Live is the primary conceptual reference, but ScreenplayOS should not copy its interface.

The deeper lesson is that a single creative project can have radically different representations optimized for different creative activities while remaining unmistakably the same project.

The views do not need to look alike. They need to behave as different representations of the same underlying creative object.

**The view changes. The filmmaker's context does not.**

Changing workspace should feel like changing the lens through which the film is being examined. Never make the user repeatedly find their place.

## One Center Stage

Every view must have one unmistakable center of attention.

Do not divide the application into several equally important regions. Do not expose every capability simply because it exists.

Ask:

**What is the filmmaker thinking about right now?**

Then allow that creative object to dominate:

- Outline: the story becomes the application.
- Script: the page becomes the application.
- Shot: the shot plan becomes the application.
- Boards: the images become the application.
- Edit: the movie in time becomes the application.

Everything else becomes contextual.

## Focused Does Not Mean Empty

Do not interpret clean as giant controls, enormous margins, oversized typography, excessive whitespace, or hiding useful professional information.

This is professional creative software. Information density is desirable when the information is useful.

The objective is:

**Less visual noise per unit of information.**

Favor precision, hierarchy, alignment, and contextual disclosure over simply making everything bigger.

## Shared Application Shell

All five views live inside one stable application shell.

Keep common:

- project identity
- workspace navigation
- undo / redo
- global commands
- save state
- project browser access
- command palette
- typography
- icon language
- color system
- interaction states
- keyboard conventions

Primary workspace navigation remains compact:

**OUTLINE   SCRIPT   SHOT   BOARDS   EDIT**

Treat these as professional workspace modes, not giant browser tabs.

The shell remains stable. The workspace transforms.

## View Responsibilities

| View | Center stage | Contextual area |
| --- | --- | --- |
| Outline | Story structure | Script Preview |
| Script | Screenplay | Navigator / Inspector |
| Shot | Shot plan | Shot Composer |
| Boards | Images | Board Details / variants |
| Edit | Viewer + Timeline | Story Spine |

### Outline

Outline answers: **What is the story?**

The outline occupies the majority of the workspace. It is not a sidebar or accessory to the screenplay.

Scene cards are direct, manipulable objects generated from the actual screenplay scenes. They may show scene heading, concise synopsis, characters, location, page count, estimated duration, and meaningful tags/status.

The right contextual pane is Script Preview. It follows scene selection and provides Open in Script while preserving the selected scene.

### Script

Script answers: **What is written?**

The screenplay visually dominates. This must be an excellent professional screenwriting application even if the filmmaker never uses Shot, Boards, or Edit.

Focus Mode should make the application a quiet writing instrument. Do not expose camera controls, storyboard tools, timeline controls, production metadata, asset management, or persistent AI chat unless specifically invoked.

Script notes are contextual annotations on screenplay material. They may appear across views, but they should not become a primary workspace or distract from the current creative object.

### Shot

Shot answers: **How do we intend to make this scene?**

The central workspace represents Scene → Shots. A shot must be able to begin simply.

The Shot Composer defines the shot: framing, camera, lens, movement, blocking, creative intent, references, and notes. It should not become the Boards workspace.

The selected scene script should remain visible in Shot. Coverage decisions happen beside the words, so the shot list and composer sit next to the script instead of replacing it.

### Boards

Boards answers: **What does the film look like?**

Board images dominate. Surrounding textual UI should recede.

Maintain the distinction:

- **Shot = Intent**
- **Board = Visual Representation**

A shot can exist without a board. A shot may have multiple board variants.

Board imagery may come from drawing, imported storyboard artwork, photography, reference imagery, AI generation, previs, frame grabs, or later footage-derived frames. AI generation is optional, never structurally required.

The selected scene script should remain visible in Boards. Board decisions happen beside the words and shot intent, so the board sequence and detail controls sit next to the script instead of becoming a detached gallery.

### Boardomatic

Boardomatic is a first-class filmmaking capability.

Before actual moving-image shots exist:

**Boards are the edit media.**

Every primary board can carry duration. Those durations create a playable visual sequence.

The central question is:

**Does the movie play?**

Do not overbuild editing functionality before this experience works beautifully.

### Edit

Edit answers: **How does the film play in time?**

The dominant objects are:

**Viewer + Timeline**

Initially, the timeline is populated primarily by Boards. The first Edit implementation is effectively Boardomatic + Timeline.

Do not attempt to replicate Premiere, Avid, Resolve, or Final Cut in V1.

The selected scene script should remain visible in Edit. Timeline decisions happen beside the words, so the viewer, timeline, and Story Spine sit next to the script instead of hiding it.

## Story Spine

Edit has one important contextual surface: the Story Spine.

The Story Spine is the filmmaker's narrative window back into the screenplay.

The timeline answers: **Where am I in time?**

The Story Spine answers: **Where am I in the story?**

These coordinate systems remain connected.

The Story Spine is contextual, resizable, and collapsible. It must never compete visually with Viewer + Timeline.

## Progressive Media

The film progressively materializes without the project being rebuilt.

A shot may evolve through:

**Shot Intent → Board → Previs → Generated Video / Production Footage → Final Media**

The canonical shot remains stable. Its best available representation changes.

## Media Substitution

If Board 14B is already present in the edit and actual footage for Shot 14B later becomes available, allow the filmmaker to replace the board with richer media while preserving editorial context wherever practical.

Preserve shot identity, scene identity, timeline position, narrative relationship, notes, markers, audio relationships, approximate timing, and transitions where appropriate.

The filmmaker should experience this as the shot becoming more complete, not importing an unrelated clip.

## Canonical Project Model

Build the application around objects, not screens.

```text
Project
  -> Sequence
  -> Scene
  -> Script Content
  -> Shot
  -> Board
  -> Media Version
  -> Edit Instance
```

Views are representations of these objects.

Do not create separate Outline Scene, Script Scene, Shot Scene, and Edit Scene records. There is one canonical Scene.

Likewise maintain one canonical Shot identity across Shot, Boards, and Edit.

**Change it once. See it everywhere.**

## Visual DNA

Use these applications as conceptual references without visibly imitating any one of them:

- Ableton Live: workspace restraint, information density, multiple representations of one project.
- DaVinci Resolve: specialized creative workspaces inside one coherent application.
- Figma: contextual inspection, direct manipulation, object hierarchy, selection behavior.
- Final Cut Pro: contextual intelligence and progressive disclosure.
- Procreate: respect for the creative object and disappearing UI.
- Blender: extensible architecture and consistent interaction language across complex professional functions.

Take the architecture, not the costume.

## Product Character

The application should feel professional, quiet, precise, fast, focused, tactile, dense when useful, minimal when possible, filmmaker-oriented, tool-like rather than website-like, and contemporary without being fashionable.

It should feel like software someone can comfortably use for eight hours.

## Anti-Patterns

It must not feel like:

- SaaS dashboard
- admin panel
- startup website
- Notion clone
- giant card grid
- mobile interface enlarged for desktop
- chatbot wrapper
- AI-generated dashboard
- collection of floating rounded rectangles

Avoid excessive gradients, glassmorphism, decorative shadows, giant typography, excessive padding, gratuitous animation, decorative color, and unnecessary modals.

## Geometry

Favor 2-4px radii, 1px separators, shared panel edges, strict alignment, consistent baselines, compact controls, nested workspace panes, and strong grid logic.

Panels should generally feel structurally attached to the application. Avoid floating-card architecture unless an object genuinely needs to float.

## Color

Build primarily from a restrained neutral system.

Establish hierarchy first through luminance.

Accent color should communicate selection, active state, meaningful action, or important status. It should not be decoration.

The application should remain understandable in grayscale.

## Typography

Use compact, highly legible professional UI typography.

Favor approximately 11-14px for most application controls where appropriate.

Hierarchy should come primarily from weight, position, spacing, and contrast, not enormous differences in type size.

The screenplay follows its own professional document typography requirements.

## Interaction

This is desktop professional software.

Prioritize keyboard shortcuts, context menus, drag/drop, multi-selection, inline editing, undo/redo, command palette, direct manipulation, predictable selection, fast pane manipulation, and intelligent defaults.

Avoid modal dialogs when an operation can happen directly in context.

## AI

AI is infrastructure. It is not a sixth workspace.

Never create:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT · AI**

AI appears contextually through selection-based actions, command palette, inline suggestions, inspector tools, and optional conversation.

The filmmaker should experience an intelligent filmmaking instrument, not a chatbot with filmmaking features.

## Component System

Create canonical components rather than inventing new UI treatments screen by screen.

Core components include:

- ApplicationShell
- WorkspaceSwitcher
- Workspace
- Panel
- SplitPane
- Toolbar
- StatusBar
- Navigator
- TreeView
- Inspector
- ScriptPreview
- ShotComposer
- StorySpine
- Button
- IconButton
- Toggle
- Checkbox
- Dropdown
- TextField
- NumericField
- SearchField
- ContextMenu
- Tooltip
- Popover
- Dialog
- CommandPalette
- Timeline
- Viewer
- SceneCard
- SceneRow
- ShotCard
- ShotRow
- BoardCard
- SelectionState
- EmptyState

Every workspace uses the shared design system even though its composition differs.

## Design Tokens

Centralize surface levels, text levels, borders, accent, semantic states, typography, spacing, control heights, radii, icon sizing, hover, selected, focused, and disabled states.

Do not hard-code arbitrary visual values inside individual features when an existing design token can represent them.

## Workspace-Specific Information

Never expose information merely because it exists.

Ask:

**Is this information useful in this mode of thought?**

If not, hide it.
