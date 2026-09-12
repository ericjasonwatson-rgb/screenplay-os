# PLATFORM ARCHITECTURE

Design and engineer this product from the beginning as **professional filmmaking software that can be delivered across multiple platforms**.

Do not treat it as a website that might later be wrapped into an app.

The target product surfaces are:

# macOS
Primary professional desktop experience.

# iPadOS
First-class creative experience.

# iOS
Focused companion experience.

# Web
Optional / complementary access where useful.

The underlying project model, screenplay model, shot model, board model, edit model, and synchronization architecture must not depend on browser-only assumptions.

---

# CORE PRINCIPLE

# ONE PROJECT MODEL. MULTIPLE PLATFORM-SPECIFIC INTERFACES.

Do not attempt to stretch one identical UI across every screen size.

The project and creative objects remain the same.

Their presentation adapts to the device.

The architecture should conceptually separate:

**PROJECT DATA**

from

**APPLICATION LOGIC**

from

**PLATFORM UI**

Conceptually:

PROJECT CORE

→ sequences  
→ scenes  
→ screenplay  
→ shots  
→ boards  
→ media  
→ edit  
→ versions

↓

SHARED COMMAND / APPLICATION LAYER

→ create scene  
→ reorder scene  
→ edit screenplay  
→ create shot  
→ create board  
→ replace media  
→ edit timeline  
→ undo / redo

↓

PLATFORM EXPERIENCES

→ macOS  
→ iPadOS  
→ iOS  
→ Web

No fundamental project object should know or care which interface is displaying it.

---

# DESKTOP IS THE CANONICAL PROFESSIONAL EXPERIENCE

The macOS application is the reference professional environment.

Do not water down the desktop application merely so the same layout can fit on a phone.

macOS should support the full five-view architecture:

# OUTLINE · SCRIPT · SHOT · BOARDS · EDIT

Desktop interaction should include, where appropriate:

- resizable panes
- collapsible panes
- multiple windows where useful
- keyboard shortcuts
- right-click / context menus
- drag and drop
- precise pointer interaction
- multi-selection
- menu-bar commands
- command palette
- full-screen workflows
- native file interaction
- copy / paste
- undo / redo
- external display support where practical

The Mac application should feel like genuine desktop creative software.

Think in terms of the interaction seriousness of:

- Ableton
- Final Cut
- Resolve
- Figma
- professional writing applications

not a webpage running inside a desktop window.

---

# IPAD IS A FIRST-CLASS CREATIVE EXPERIENCE

Do not treat iPad as a read-only companion.

The iPad should eventually support serious creative work.

The same five conceptual views can exist:

**OUTLINE · SCRIPT · SHOT · BOARDS · EDIT**

but their physical layouts should adapt to touch.

Do not squeeze desktop sidebars into narrow columns.

Instead use:

- contextual drawers
- slide-over inspectors
- expandable panes
- full-screen mode changes
- touch-friendly hit targets
- gestures
- drag and drop
- hardware keyboard shortcuts
- Apple Pencil where useful

The iPad should feel intentionally designed for touch.

Particularly strong iPad use cases may include:

### Outline
Direct manipulation and rearrangement of scenes.

### Script
Distraction-free writing and revision.

### Shot
On-set or preproduction shot planning.

### Boards
Storyboard review, image manipulation, annotations and Pencil markup.

### Edit
Boardomatic playback and a simplified touch-optimized timeline.

The iPad UI may present fewer controls at once than macOS while retaining the same underlying project capability.

---

# IPHONE IS A COMPANION EXPERIENCE

Do not attempt to reproduce the complete desktop application on iPhone.

Design intentionally for the situations where a filmmaker has a phone in their hand.

Likely strong initial capabilities include:

- screenplay reading
- light script editing
- scene navigation
- notes
- comments
- shot-list review
- shot creation / adjustment
- boards
- visual references
- production reference
- quick capture
- project review

Possible later capabilities may include simplified Boardomatic playback or edit review.

But do not sacrifice the desktop architecture merely to make every function available on a phone.

The iPhone should be **excellent at a focused subset** rather than mediocre at everything.

---

# WEB

The architecture may support a web application, but web should not dictate the product model.

The web version may be useful for:

- access from another computer
- collaboration
- review
- lightweight editing
- sharing
- project administration
- team workflows

Do not introduce browser-specific architectural constraints into the canonical project model merely to simplify the web client.

---

# ONE FILM, FIVE VIEWS, EVERYWHERE

The core conceptual model remains:

# OUTLINE · SCRIPT · SHOT · BOARDS · EDIT

Those five views are properties of the film project, not properties of the Mac UI.

Different platforms may arrange them differently.

For example:

## macOS

OUTLINE  
Large structural workspace + persistent Script Preview.

SCRIPT  
Screenplay center stage + optional side panes.

SHOT  
Shot structure + persistent Shot Composer.

BOARDS  
Large visual storyboard workspace.

EDIT  
Viewer + Story Spine + timeline.

## iPadOS

OUTLINE  
Full-screen outline with optional slide-over Script Preview.

SCRIPT  
Full-screen screenplay with contextual drawers.

SHOT  
Shot plan with expandable/full-screen Shot Composer.

BOARDS  
Touch-first storyboard environment.

EDIT  
Viewer + simplified timeline with expandable Story Spine.

## iOS

OUTLINE  
Scene list / lightweight structure.

SCRIPT  
Reading + focused editing.

SHOT  
Shot-list mode.

BOARDS  
Swipeable board sequence.

EDIT  
Primarily review/playback initially.

The view is conceptually the same.

The interface adapts.

---

# LOCAL-FIRST

The application should be designed **local-first**.

Professional creative work must not depend on a continuous network connection.

A user should be able to:

- open a project
- write
- outline
- create shots
- work with boards
- review an edit
- save work

without internet connectivity.

Cloud capability should enhance the local application rather than be required for basic operation.

Conceptually:

# LOCAL PROJECT
↓
continuous local save
↓
version history
↓
optional cloud sync
↓
other devices / collaboration

Never make network latency part of the core writing experience.

---

# SAVING

The application should save continuously and safely.

Avoid requiring the user to think constantly about manual saving.

Support:

- automatic local persistence
- crash recovery
- undo/redo
- project version history
- deliberate snapshots / named versions where useful

Professional creative data must be treated as valuable.

Data loss is unacceptable.

---

# SYNC

Cloud synchronization should eventually allow the same project to move between:

**Mac ↔ iPad ↔ iPhone ↔ Web**

while preserving canonical object identity.

For example:

Scene 14 remains Scene 14 everywhere.

Shot 14B remains Shot 14B everywhere.

Board 14B remains associated with Shot 14B.

Do not create device-specific copies of canonical objects.

Synchronization should operate on project objects and versions rather than on independent exported documents wherever possible.

---

# OFFLINE + CONFLICTS

Assume devices can edit while offline.

Therefore design synchronization around explicit object identity, revisions, and conflict handling.

Do not assume:

**last upload blindly wins**

for important creative content.

At minimum, architecture should be capable of supporting:

- object versioning
- timestamps/revisions
- conflict detection
- recoverable prior states

The exact sync strategy can evolve, but the data model must not make robust synchronization impossible.

---

# SCREENPLAY ENGINE REQUIREMENT

Do not choose technology solely because it makes cross-platform packaging easy.

The screenplay editor is a critical technical constraint.

It must ultimately support professional behavior such as:

- responsive typing
- screenplay element formatting
- pagination
- accurate page layout
- keyboard navigation
- selection
- copy/paste
- undo/redo
- autocomplete
- revisions
- comments
- very large scripts
- stable cursor behavior
- reliable document persistence

Evaluate the implementation stack against the needs of this editor.

Do not accept a mediocre screenplay editor simply to preserve theoretical platform code reuse.

# SCREENWRITING QUALITY TAKES PRIORITY OVER MAXIMUM UI CODE SHARING.

Shared data/application logic is highly desirable.

Shared presentation code is desirable only when it does not compromise platform quality.

---

# NATIVE PLATFORM BEHAVIOR

Where beneficial, use platform-native capabilities.

On macOS consider:

- system menus
- keyboard shortcuts
- native window behavior
- drag/drop
- file integration
- accessibility
- full-screen behavior

On iPadOS consider:

- Pencil
- touch gestures
- hardware keyboard
- drag/drop
- multitasking
- external displays where appropriate

On iOS consider:

- touch-first interaction
- sharing
- quick capture
- camera/media import
- compact navigation

Users should not feel that the app is fighting the device.

---

# RESPONSIVE VS ADAPTIVE

Favor **adaptive** interface design over merely responsive scaling.

Responsive means:

"make this same layout narrower."

Adaptive means:

"present this creative activity in the best form for this device."

Use adaptive design.

For example:

A persistent Shot Composer on Mac may become a temporary full-height inspector on iPad.

A Story Spine + Viewer + Timeline layout on Mac may become separate coordinated surfaces on iPad.

This is correct.

The conceptual model remains consistent even when the physical layout changes.

---

# DESIGN SYSTEM

Maintain one shared design language across platforms:

- typography family
- icon language
- semantic colors
- object terminology
- selection logic
- hierarchy
- workspace identity
- interaction concepts

But permit platform-specific dimensions and behavior.

A Mac control does not need to have the same physical size as its touch equivalent.

Consistency means the product is recognizable and predictable.

It does not mean pixel-identical UI.

---

# PERFORMANCE

Treat performance as part of the product design.

Creative interactions should feel immediate.

Prioritize:

- low-latency typing
- fast project opening
- responsive scene selection
- instant workspace switching
- smooth board browsing
- smooth timeline interaction
- asynchronous media loading
- efficient autosave

Do not block core interaction while uploading or synchronizing media.

---

# MEDIA STORAGE

Remember that filmmaking projects may become large.

Boards, audio, video, reference images and generated material can grow far beyond screenplay data.

Architect storage so that project metadata and large media assets do not need to behave identically.

Conceptually separate:

**STRUCTURED PROJECT DATA**

from

**MEDIA ASSETS**

while preserving relationships between them.

A project should be able to know:

Shot 14B uses Media Version X

without forcing the entire video file into the same storage representation as the shot metadata.

---

# DISTRIBUTION

Plan for eventual downloadable distribution.

The product should be capable of becoming:

- a signed/notarized macOS application
- an App Store macOS application if desired
- an iPadOS application
- an iOS application

Do not make assumptions during development that require the finished product to run only through a hosted URL.

The product is software.

The website is one possible delivery surface.

---

# BUSINESS MODEL INDEPENDENCE

The architecture should not assume all functionality requires a subscription.

The core writing application may remain free while optional production/OS capabilities can be monetized separately.

Therefore entitlement/subscription logic should remain separate from canonical project data.

A project created with the free screenplay editor must remain a real project.

Do not create separate incompatible "free project" and "paid project" formats.

---

# FILE FORMAT

Do not base the canonical internal project model around Final Draft FDX.

Support importing and exporting formats where useful, including FDX if appropriate, but maintain our own canonical project representation.

The project format must be capable of expressing:

- screenplay
- sequences
- scenes
- shots
- boards
- media relationships
- timeline/edit information
- metadata
- versions

A screenplay file format alone is insufficient for the eventual product.

---

# IMPLEMENTATION RULE

Before committing to a platform framework, evaluate the candidate architecture against:

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

---

# PRODUCT PRINCIPLE

The user should never need to know whether a particular creative object originated on Mac, iPad, phone, or web.

The film project is canonical.

Devices are windows into it.

# ONE FILM.
# ONE PROJECT MODEL.
# MULTIPLE DEVICES.

---

# PLATFORM NORTH STAR

We are not building:

**a website that may someday become an app.**

We are building:

# PROFESSIONAL FILMMAKING SOFTWARE THAT CAN EXIST ON MULTIPLE PLATFORMS.

The Mac is the full professional workstation.

The iPad is a first-class creative tool.

The iPhone is a focused filmmaking companion.

The web provides access and collaboration where useful.

Across all of them:

# OUTLINE · SCRIPT · SHOT · BOARDS · EDIT

remain five representations of the same film.