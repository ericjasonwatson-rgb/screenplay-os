# Platform Architecture

ScreenplayOS should be engineered as professional filmmaking software that can exist across multiple platforms. It should not be treated as a website that might later be wrapped into an app.

The target product surfaces are:

- macOS: primary professional desktop experience
- iPadOS: first-class creative experience
- iOS: focused companion experience
- Web: optional and complementary access where useful

## Core Principle

**One project model. Multiple platform-specific interfaces.**

The project and creative objects remain the same. Their presentation adapts to the device.

Conceptually separate:

```text
Project Data
  -> sequences
  -> scenes
  -> screenplay
  -> shots
  -> boards
  -> media
  -> edit
  -> versions

Shared Command / Application Layer
  -> create scene
  -> reorder scene
  -> edit screenplay
  -> create shot
  -> create board
  -> replace media
  -> edit timeline
  -> undo / redo

Platform Experiences
  -> macOS
  -> iPadOS
  -> iOS
  -> Web
```

No fundamental project object should know or care which interface is displaying it.

## Desktop Reference

The macOS application is the canonical professional environment. Do not water it down merely so the same layout can fit on a phone.

macOS should support the full five-view architecture:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

Desktop interaction should include resizable panes, collapsible panes, keyboard shortcuts, context menus, drag and drop, pointer precision, multi-selection, menu-bar commands, a command palette, native file behavior, copy/paste, undo/redo, and full-screen workflows where useful.

The Mac application should feel like genuine desktop creative software, not a webpage running inside a desktop window.

## iPadOS

iPad should become a first-class creative experience, not a read-only companion.

The same conceptual views can exist, but their physical layouts should adapt to touch:

- Outline: direct manipulation and rearrangement of scenes
- Script: focused writing and revision
- Shot: preproduction and on-set shot planning
- Boards: storyboard review, annotation, and Pencil markup
- Edit: Boardomatic playback and simplified touch timeline

Do not squeeze desktop sidebars into narrow columns. Use contextual drawers, slide-over inspectors, expandable panes, full-screen mode changes, gestures, drag and drop, hardware keyboard support, and Apple Pencil where useful.

## iOS

iPhone should be an excellent focused companion rather than a mediocre full desktop clone.

Strong initial capabilities include screenplay reading, light editing, scene navigation, notes, shot-list review, shot adjustment, boards, visual references, production reference, quick capture, and project review.

Possible later capabilities include simplified Boardomatic playback and edit review.

## Web

The web version may be useful for access, collaboration, review, lightweight editing, sharing, administration, and team workflows.

Web should not dictate the canonical project model, the screenplay engine, or storage assumptions.

## Local-First

Professional creative work must not depend on a continuous network connection.

A filmmaker should be able to open a project, write, outline, create shots, work with boards, review an edit, and save work offline.

Cloud capability should enhance the local application rather than be required for basic operation:

```text
Local project
  -> continuous local save
  -> version history
  -> optional cloud sync
  -> other devices / collaboration
```

Never make network latency part of the core writing experience.

## Saving And Sync

Professional creative data is valuable. Data loss is unacceptable.

The application should support automatic local persistence, crash recovery, undo/redo, project version history, and deliberate snapshots or named versions where useful.

Cloud synchronization should eventually allow the same project to move between Mac, iPad, iPhone, and Web while preserving canonical object identity:

- Scene 14 remains Scene 14 everywhere.
- Shot 14B remains Shot 14B everywhere.
- Board 14B remains associated with Shot 14B.

Synchronization should operate on project objects and versions rather than independent exported documents wherever possible.

Because devices may edit offline, the architecture must be capable of object versioning, timestamps or revisions, conflict detection, and recoverable prior states. Avoid any design where last upload blindly wins for important creative content.

## Screenplay Engine Priority

Do not choose technology solely because it makes cross-platform packaging easy.

The screenplay editor must ultimately support responsive typing, screenplay formatting, pagination, accurate page layout, keyboard navigation, selection, copy/paste, undo/redo, autocomplete, revisions, comments, large scripts, stable cursor behavior, and reliable persistence.

**Screenwriting quality takes priority over maximum UI code sharing.**

Shared data and application logic are highly desirable. Shared presentation code is useful only when it does not compromise platform quality.

## Adaptive Interfaces

Favor adaptive interface design over simply responsive scaling.

Responsive means making the same layout narrower. Adaptive means presenting the creative activity in the best form for the device.

A persistent Shot Composer on Mac may become a temporary full-height inspector on iPad. A Story Spine plus Viewer plus Timeline layout on Mac may become separate coordinated surfaces on iPad.

The conceptual model remains consistent even when the physical layout changes.

## Media Storage

Filmmaking projects may become large. Boards, audio, video, reference images, and generated material can grow far beyond screenplay data.

Separate structured project data from media assets while preserving relationships between them.

A project should be able to know that Shot 14B uses Media Version X without forcing the entire video file into the same storage representation as shot metadata.

## Distribution And Business Model

Plan for downloadable distribution: signed and notarized macOS app, possible Mac App Store app, iPadOS app, and iOS app.

The product is software. The website is one possible delivery surface.

Entitlement and subscription logic should remain separate from canonical project data. A project created with a free screenplay editor must remain a real project, not a separate incompatible format.

## File Format

Do not base the canonical internal project model around Final Draft FDX.

Support importing and exporting formats where useful, including FDX if appropriate, but maintain ScreenplayOS's own canonical project representation.

The project format must be capable of expressing screenplay, sequences, scenes, shots, boards, media relationships, timeline/edit information, metadata, and versions. A screenplay file format alone is insufficient for the eventual product.

## Implementation Rule

Before committing to a platform framework, evaluate it against:

1. Professional screenplay editing quality.
2. macOS desktop behavior.
3. iPad creative interaction.
4. Local-first storage.
5. Offline operation.
6. Cross-device synchronization.
7. Large media handling.
8. Timeline performance.
9. App distribution.
10. Future maintainability.

Do not choose a stack merely because it produces the fastest prototype.

## North Star

We are not building a website that may someday become an app.

We are building professional filmmaking software that can exist on multiple platforms.

The Mac is the full professional workstation. The iPad is a first-class creative tool. The iPhone is a focused filmmaking companion. The web provides access and collaboration where useful.

Across all of them:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

remain five representations of the same film.
