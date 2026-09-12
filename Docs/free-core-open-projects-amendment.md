# screenplayOS ARCHITECTURE AMENDMENT

## FREE CORE · OPEN PROJECTS · LOCAL AUTHORING · CONNECTED CLOUD

Apply this amendment to the existing screenplayOS architecture.

Do not replace the current five-view product model.

The primary application architecture remains:

# OUTLINE · SCRIPT · SHOT · BOARDS · EDIT

These remain five synchronized representations of one canonical film project.

This amendment defines how that project should exist across:

- the free product
- paid capabilities
- local storage
- downloadable applications
- browser experiences
- cloud synchronization
- sharing/review
- AI and other server-side processing

The goal is to prevent short-term implementation decisions from making the product difficult to distribute, synchronize, monetize, open, or extend later.

---

# 1. CORE PRODUCT PRINCIPLE

screenplayOS must remain usable as an excellent local screenwriting application independent of cloud services.

A user should be able to:

- create a screenplay
- open an existing screenplay
- write
- outline
- navigate scenes
- use basic shot-list capability
- save
- reopen
- export their work

without:

- creating an account
- purchasing a subscription
- configuring AI
- connecting to the internet
- uploading their screenplay to our servers

Cloud services enhance the product.

They do not define whether the user's screenplay exists.

---

# 2. SEPARATE FOUR ARCHITECTURAL LAYERS

Architect the system with explicit separation between:

## A. CANONICAL PROJECT MODEL

The creative truth of the film.

Examples:

PROJECT  
SEQUENCE  
SCENE  
SCRIPT CONTENT  
SHOT  
BOARD  
MEDIA REFERENCE  
EDIT INSTANCE  
COMMENT / ANNOTATION REFERENCES  
VERSION METADATA

## B. APPLICATION / COMMAND LAYER

Operations performed on the project.

Examples:

CreateScene  
MoveScene  
EditScript  
CreateShot  
CreateBoard  
SetBoardDuration  
AttachMedia  
ReplaceShotMedia  
CreateEditInstance

## C. PLATFORM PRESENTATION

How the project is represented on:

- macOS
- iPadOS
- iOS
- browser

## D. SERVICES

Capabilities that may depend on external infrastructure:

- account identity
- synchronization
- collaboration
- hosted review
- cloud backup
- AI generation
- large-media processing
- billing / entitlement
- analytics where permitted

Do not allow these layers to become tightly coupled.

The screenplay should not need to know whether its user has a paid subscription.

A Scene should not need to know whether it is displayed in SwiftUI or a browser.

A local edit should not depend on an AI service being available.

---

# 3. OPEN PROJECT FORMAT

Treat project portability as a foundational feature.

The canonical screenplayOS project format should be:

- documented
- versioned
- deterministic where practical
- migration-capable
- independent of subscription status
- independent of cloud storage
- readable by future versions of screenplayOS

Do not use Final Draft FDX as the canonical internal project format.

FDX may be supported as import/export.

The screenplayOS project format must eventually express more than a screenplay:

- outline structure
- screenplay
- scenes
- shots
- boards
- board timing
- media relationships
- edit structure
- project metadata
- versions

Do not embed product entitlements into the project data in a way that prevents the user's own work from being opened when a subscription lapses.

---

# 4. FREE VS PAID MUST NOT CREATE DIFFERENT PROJECT TYPES

There is one screenplayOS project format.

Do NOT create:

FreeProject  
StudioProject  
CloudProject

as separate incompatible formats.

A free project can become richer if paid capabilities are used.

If the user later stops paying, the project remains their project.

Paid status controls access to capabilities or services.

It must not determine ownership of the underlying creative data.

---

# 5. ENTITLEMENTS ARE A SEPARATE SERVICE

Implement subscription / entitlement state outside the canonical creative model.

Conceptually:

USER / ACCOUNT
    ↓
ENTITLEMENTS
    ↓
AVAILABLE CAPABILITIES

PROJECT
    ↓
CREATIVE DATA

Do not make creative objects depend structurally on billing state.

Example:

Bad:

Shot.isPaidFeature = true

Better:

The application checks whether the current user is entitled to invoke a particular advanced operation.

The shot itself remains an ordinary canonical object.

This allows:

- free writing
- paid enhancements
- changing pricing later
- educational access
- team plans
- trials
- promotional access

without corrupting the project model.

---

# 6. LOCAL-FIRST AUTHORING

The installed application should treat local persistence as authoritative for immediate creative work.

Writing must not wait for:

- network requests
- sync acknowledgements
- cloud database commits
- billing checks
- AI responses

User actions should commit locally first.

Conceptually:

USER ACTION
    ↓
LOCAL PROJECT UPDATE
    ↓
LOCAL SAVE / JOURNAL
    ↓
UI CONFIRMATION
    ↓
OPTIONAL ASYNC SYNC

Do not block typing while synchronizing.

Do not make ordinary undo/redo depend on server state.

---

# 7. LOCAL SAVE, SYNC, AND BACKUP ARE DIFFERENT STATES

Model these separately.

The application should eventually be capable of distinguishing:

**Saved locally**

from

**Synced to cloud**

from

**Backed up / recoverable remotely**

These are not synonymous.

Do not tell the user their work is safe in the cloud merely because a local save completed.

Design persistence state so the UI can represent these conditions truthfully.

---

# 8. REVISION IDENTITY

Prepare the canonical model for synchronization by giving important objects stable identities.

Examples:

ProjectID  
SequenceID  
SceneID  
ShotID  
BoardID  
MediaID  
EditInstanceID

Do not identify canonical creative objects solely by:

- array position
- scene number
- display name
- filename

Scene 14 may later become Scene 17 after reordering.

Its identity must survive.

Shot 14B may later change numbering.

Its identity must survive.

Stable identities are necessary for:

- cross-view synchronization
- cross-device sync
- comments
- collaboration
- AI job association
- media replacement
- version history

---

# 9. REVISION / VERSION MODEL

Prepare for offline editing and asynchronous services.

A useful conceptual model is:

Object identity + revision identity.

For example:

SceneID = permanent identity

SceneRevision = particular state of that scene

Do not blindly implement "last write wins" as the final synchronization strategy for important creative content.

The architecture should be able to detect:

- base revision
- local revision
- remote revision
- conflicting changes

The exact conflict-resolution strategy can evolve.

Do not prematurely build complex real-time collaboration.

But do not make it impossible later.

---

# 10. MAC APP IS PRIMARY AUTHORING CLIENT

The Mac application remains the first complete professional authoring environment.

It should be capable of functioning without cloud services.

Do not restructure the Mac application as a thin client whose basic screenplay operations require a server.

However, ensure that the project and command layers are not so tightly bound to macOS UI code that future clients cannot use the same conceptual model.

---

# 11. WEB DOES NOT NEED TO DUPLICATE THE MAC APP

Do not assume the first browser product must implement:

OUTLINE + SCRIPT + SHOT + BOARDS + EDIT

at full desktop capability.

The browser can begin with a narrower job.

Recommended initial browser surface:

# REVIEW

Support eventually:

- screenplay reading
- selected scene review
- board review
- boardomatic playback
- contextual comments
- version comparison
- approval / feedback workflows where useful

This lets collaborators participate without installing the full application.

Do not distort the desktop architecture merely to make every feature immediately available on the web.

---

# 12. PUBLISHED REVIEW VERSION

Introduce the architectural concept of a:

# PUBLISHED REVIEW VERSION

This is not another project.

It is a specific immutable or clearly versioned representation of a project prepared for sharing.

Conceptually:

PROJECT
    ↓
PROJECT REVISION
    ↓
PUBLISHED REVIEW VERSION
    ↓
SHARE LINK / REVIEW SESSION

Comments should reference the published version and relevant canonical objects where possible.

For example:

ReviewVersion 12  
→ SceneID XYZ  
→ ShotID ABC  
→ time 00:01:42

This avoids ambiguity if the creator continues editing while collaborators review an earlier version.

Do not require live collaborative editing to support useful review.

---

# 13. SHARING SHOULD BE GRANULAR

Prepare the architecture to allow sharing of:

- whole project review
- screenplay
- sequence
- scene
- boards
- boardomatic
- edit review

Do not assume that sharing one scene requires granting access to every piece of the film.

Permissions should eventually support explicit scope.

Do not implement full permission complexity unless required now.

But avoid data structures that assume all-or-nothing project exposure.

---

# 14. GUEST REVIEW

Prepare for collaborators who do not have screenplayOS accounts.

A review link may eventually allow:

- view
- play
- comment

with limited permissions.

Creating an account should not necessarily be required merely to watch a boardomatic or review a script passage.

However, anonymous/guest access must be explicitly authorized by the project owner.

Do not make projects public by default.

---

# 15. CLOUD SERVICES

Treat cloud functionality as independent services rather than as the project itself.

Potential cloud services include:

## SYNC SERVICE

Keeps authorized project revisions consistent across devices.

## REVIEW SERVICE

Hosts published review versions and comments.

## MEDIA SERVICE

Stores or streams intentionally uploaded media.

## AI JOB SERVICE

Submits and tracks generation/analysis jobs.

## ACCOUNT SERVICE

Identity and team membership.

## ENTITLEMENT SERVICE

Paid capability access.

These can share infrastructure later, but preserve conceptual boundaries now.

---

# 16. ASYNCHRONOUS AI JOBS

AI generation must not behave like synchronous document editing.

Represent AI work as jobs.

Conceptually:

USER REQUEST
    ↓
AI JOB
    ↓
INPUT REFERENCES
    ↓
PROCESSING
    ↓
OUTPUT
    ↓
USER REVIEW
    ↓
OPTIONAL ADOPTION INTO PROJECT

Important:

AI output is not automatically canonical project truth.

Generated material should be proposed output until intentionally accepted where appropriate.

A generation job should record enough context to determine:

- which Project
- which Scene
- which Shot
- which Board
- which revision of those objects

the request was based on.

This prevents delayed AI results from being silently inserted into the wrong creative context.

---

# 17. AI MUST NOT SILENTLY MUTATE THE PROJECT

AI operations that alter creative content must be:

- visible
- reviewable
- reversible
- attributable

Do not allow an asynchronous service to overwrite screenplay content merely because a job completed.

For generated visual material, attach results as candidates/versions until explicitly adopted where appropriate.

---

# 18. LARGE MEDIA IS NOT THE PROJECT DATABASE

Separate structured creative data from media blobs.

Conceptually:

PROJECT DATA
- text
- IDs
- relationships
- timing
- metadata

MEDIA
- images
- audio
- video
- generated assets
- proxies

Project data references media using stable media identifiers and metadata.

Do not serialize multi-gigabyte video directly into the same representation as screenplay text and scene records.

Support local media references first where appropriate.

Cloud-uploaded media can become another storage location for the same canonical media identity.

---

# 19. MEDIA LOCATION

Prepare for media to exist in one or more locations:

- local only
- cloud only
- local + cloud
- proxy available
- source offline

The project should be able to represent that distinction.

A missing local media file should not corrupt the entire film project.

The system should be able to say:

"Media unavailable"

rather than losing the Shot or Edit Instance that referenced it.

---

# 20. BOARDOMATIC REMAINS THE FIRST EDIT

The existing product architecture remains:

SHOT
→ BOARD
→ BOARDOMATIC
→ richer media
→ final edit

The initial Edit can function with boards even if no video exists.

When richer media becomes available, it can progressively substitute for boards without requiring reconstruction of narrative/editorial structure.

This continuity must survive both local and cloud workflows.

---

# 21. DOWNLOADABLE APPLICATION + BROWSER ARE COMPLEMENTARY

Do not design:

Mac app vs web app

as competing product architectures.

Think:

# AUTHORING CLIENTS + PARTICIPATION CLIENTS + SHARED SERVICES

Initially:

Mac app
= full authoring.

Browser
= frictionless review and participation.

Later:

iPad
= first-class adapted creation.

iPhone
= focused companion.

Browser authoring
= possible expansion if user demand justifies it.

All clients operate on compatible canonical objects.

---

# 22. ACCOUNT OPTIONALITY

A user should be able to use the local free writing core without an account unless a specific platform constraint prevents it.

An account may be required for:

- sync
- hosted backup
- sharing
- collaboration
- paid services
- cloud AI usage

Do not require account creation merely to open the application and write locally.

This is both a usability and trust principle.

---

# 23. OPEN SOURCE IS NOT REQUIRED BY THIS ARCHITECTURE

Do not open-source or restructure the application solely because the commercial strategy may eventually include open-source components.

Instead:

1. Maintain a clean canonical project format.
2. Document interoperability boundaries.
3. Keep proprietary service dependencies outside the core data model.
4. Avoid closed assumptions that make external tooling impossible.

This keeps multiple future options available:

- closed-source free app
- open-format app
- selectively open-source tools
- open-source writing core
- broader open-core model

The current architecture should not force a decision prematurely.

---

# 24. EXTENSION BOUNDARY

Where practical, keep transformations and integrations behind clear interfaces.

Examples:

Importers  
Exporters  
AI providers  
Media processors  
Analysis tools

Do not hard-wire the canonical project model to one AI vendor.

A Shot should not contain provider-specific Runway fields as its core definition.

Instead:

Shot
→ GenerationRequest
→ ProviderAdapter
→ ProviderResult
→ MediaCandidate

This lets providers evolve without requiring changes to the fundamental project model.

---

# 25. PRIVACY BOUNDARY

The canonical local project must not automatically be uploaded to an AI or cloud provider.

Any network operation involving creative content should pass through an explicit service boundary.

The architecture should eventually allow the UI to explain:

- what content is being sent
- which service receives it
- why it is required
- what result is expected

Do not make third-party AI calls implicitly as part of ordinary typing.

---

# 26. ANALYTICS BOUNDARY

If product analytics are added later, keep them separate from creative content.

Prefer event-level usage telemetry such as:

WorkspaceOpened  
BoardCreated  
ReviewPublished

rather than collecting screenplay text.

Never architect ordinary analytics around transmitting users' screenplay contents.

---

# 27. COMMERCIAL MODEL

The architecture should support:

# FREE CORE

Excellent screenplay writing and outlining.

Basic shot-list capability.

Local projects.

Portable data.

## STUDIO / PAID CAPABILITIES

Potential future examples:

Advanced production workflows.

Richer visual development.

Cloud synchronization.

Version/recovery services.

Collaboration.

Hosted review.

Advanced editorial tools.

Advanced AI orchestration.

## METERED SERVICES

Potentially expensive external operations such as:

Video generation.

Large-scale image generation.

Heavy media processing.

Do not encode specific pricing into the architecture.

Pricing will change.

Capabilities should be expressed as entitlements.

---

# 28. CANCELLATION / DOWNGRADE

Design so that subscription cancellation does not make the user's existing creative work inaccessible.

A former paid user should still be able to:

- open their local project
- read the screenplay
- access their own project data
- export supported formats

Paid-only operations can become unavailable.

Do not encrypt or structurally lock user-created project content behind subscription state.

Cloud-retention policies may have separate limits, but they must be clear and should not define ownership of local work.

---

# 29. ARCHITECTURAL TEST

For every major new feature ask:

## DATA

Is this canonical creative data or merely UI/service state?

## LOCAL

Can ordinary writing still function if the network is unavailable?

## IDENTITY

Does this object have stable identity across views and devices?

## PORTABILITY

Can the user's work survive without the service that created it?

## ENTITLEMENT

Are we checking access to a capability rather than changing the meaning of project data?

## SYNC

Could this operation be reconciled safely if another device edited the project?

## REVIEW

If shared externally, which revision is being reviewed?

## AI

Can asynchronous output arrive safely without silently overwriting newer work?

## PRIVACY

Is creative content leaving the device? If yes, is that explicit?

If a proposed architecture fails one of these tests, revise it before implementation.

---

# 30. DO NOT OVERBUILD NOW

This amendment establishes boundaries.

It is not authorization to immediately build:

- user accounts
- payments
- cloud sync
- live collaboration
- web editor
- media hosting
- AI orchestration
- permission matrices

The immediate product priority remains:

# EXCELLENT SCREENWRITING.

Build architecture that preserves these future options without distracting from the current writing-first milestone.

Avoid speculative infrastructure that adds complexity before it is needed.

---

# IMPLEMENTATION TASK FOR THE CURRENT REPOSITORY

Inspect the existing repository and answer:

1. Where is canonical project data currently defined?
2. Is UI state mixed into project data?
3. Are scenes/shots using stable identities?
4. Is persistence local-first?
5. Are any current types tied unnecessarily to a particular UI framework?
6. Is there already an entitlement/account dependency in the core model?
7. Are external-service assumptions present?
8. Can the existing project representation evolve into a documented portable format?
9. Are media references separate from structured screenplay data?
10. What is the minimum change needed now to preserve the architecture described above?

Do not conduct a broad rewrite.

If the current model is compatible, document that and leave it alone.

If a small foundational correction is necessary—such as stable IDs, separating transient UI state, or abstracting a service dependency—make the smallest safe change and add appropriate tests.

Finish with:

- architecture findings
- changes made
- changes deliberately deferred
- tests run
- risks
- the single next architectural decision that will eventually need to be made

---

# NORTH STAR

screenplayOS should be able to grow from:

# A GREAT FREE LOCAL SCREENWRITING APP

into:

# A CONNECTED MODERN FILMMAKING ENVIRONMENT

without forcing writers to surrender ownership, portability, offline access, or clarity.

The architecture should make all of these true at the same time:

**WRITE LOCALLY.**

**OWN THE PROJECT.**

**CONNECT WHEN USEFUL.**

**SHARE WITHOUT FRICTION.**

**PAY FOR LEVERAGE, NOT ACCESS TO YOUR OWN WORK.**

**USE AI WITHOUT MAKING AI THE FOUNDATION OF THE DOCUMENT.**

# ONE FILM.
# ONE CANONICAL PROJECT.
# MANY WAYS TO WORK WITH IT.