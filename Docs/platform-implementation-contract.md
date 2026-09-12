# Platform architecture: implementation contract

Adopted 2026-09-12 from the supplied Platform Architecture direction. This contract connects that direction to UI implementation and the revised Open Screenplay Format draft. It describes required direction, not completed platform support.

## Governing documents

- platform-architecture.md: complete user-supplied platform direction, preserved verbatim.
- ui-ux-design-constitution.md: focus, density, context, and interaction principles.
- product-architecture.md: five views of one film.
- open-screenplay-format-1.0-revised-draft.md: portable screenplay document contract, still a draft.

## One project; independent screenplay recovery

The complete film project is richer than a screenplay package. It owns sequences, scenes, screenplay, shots, boards, media relationships, edit/timeline information, metadata, and versions. Its screenplay and manually authored shot lists must remain independently recoverable through the open screenplay format.

Use the same permanent object identities across these representations. Do not create a second editable screenplay merely to power another platform or view. The document format is a persistence/interoperability contract, not a requirement that every project object occupy one JSON file or one package.

The final complete-project storage layout and companion-data linkage remain design work. Do not invent a competing released format or force OS analysis, entitlements, media binaries, or generated boards into the screenplay core. Optional companion data must not be required to read the screenplay. Authored creative work must remain recoverable without a paid tier, including authored extension material.

Displayed scene numbers and shot labels are not identity. The platform examples such as Scene 14 and Shot 14B mean the same objects stay associated everywhere, even when numbering changes. UUIDs and explicit references provide that continuity.

## Dependency direction

Platform UI calls application commands. Application commands operate on project data and storage services. Project data must not import or depend on a UI framework, browser API, window, widget, payment SDK, or platform file picker.

The shared application layer owns creative mutations, validation, reference maintenance, undo transactions, and revision/conflict semantics. Native adapters own keyboard/touch events, IME and selection conversion, menus, windows, file dialogs, Pencil input, and platform lifecycle. Storage, media, and future sync are explicit services rather than UI side effects.

Keep local workspace presentation state—pane widths, focused control, window arrangement, zoom—separate from authored project data. Selection uses stable object identity, with an explicit fallback when the object was removed. Switching views preserves scene/shot/board context wherever possible.

Do not port the whole existing Mac view model as the shared application layer. Extract bounded, tested creative commands as the relevant feature is revised. A command must perform its text/object mutation and reference repairs as one undoable transaction. Different UI surfaces must invoke that same operation rather than copy its logic.

## Platform presentation

| Activity | macOS | iPadOS | iOS |
|---|---|---|---|
| Outline | Structural workspace and persistent Script Preview | Full-screen structure with optional preview drawer | Scene list and light structural actions |
| Script | Writing surface with optional panes; keyboard precision | Full-screen writing, contextual drawers, hardware keyboard | Reading and focused editing |
| Shot | Shot plan and persistent Shot Composer | Expandable or full-screen composer | Shot list, capture, and focused adjustments |
| Boards | Large visual workspace and contextual details | Touch manipulation and Pencil annotations where useful | Swipeable sequence and review |
| Edit | Viewer, Story Spine, timeline | Touch timeline with expandable supporting surfaces | Review/playback first |

Web is complementary access, editing, and collaboration when justified. It does not define storage, object identity, or desktop interaction.

One design language shares terms, semantic colors, icon meaning, hierarchy, and selection semantics. Control dimensions, pane arrangements, gestures, and navigation are platform-specific. Do not scale desktop columns down to phone widths. Preserve the complete Mac experience.

## Rules for the next Mac UI changes

- Preserve Outline, Script, Shot, Boards, and Edit as coordinated views of the same objects, each with one primary creative focus.
- Pane changes must support a laptop-sized window without clipping labels or making the active editor inaccessible. Collapsing an inspector must retain selection and draft state. Horizontal scrolling in current wide workspaces is an interim accommodation, not the intended tablet design.
- Use system menus, shortcuts, context menus, copy/paste, accessible labels, clear focus, and native file behavior. Add multi-selection, drag/drop, multiple windows, and external-display handling only with explicit interaction and data-ownership rules.
- Keep commands separate from toolbar/menu placement. Do not embed canonical object creation or mutation in a platform view just to simplify that view.
- Touch and keyboard must be alternative ways to invoke the same creative operation; do not require hover or a right-click for an essential touch workflow.
- Preserve native screenplay input quality, IME composition, Unicode selection, caret stability, and Undo/Redo. Shared presentation code is optional; professional editing quality is mandatory.

## Local persistence, media, and sync

Writing, outlining, shots, local boards, local edit review, and saves must work offline. Features using unavailable remote media or services must explain the specific unavailable resource without blocking unrelated local work.

Local persistence and recoverable history precede optional cloud sync. Save completion and sync completion are separate states. Uploads, media decoding, downloads, and conflict resolution must not block core typing. Large media is stored independently from structured project metadata and referenced by stable asset/version identity.

Future synchronization must detect concurrent edits using object revisions/causal information or another explicitly justified strategy. Wall-clock timestamps alone do not resolve concurrent creative edits. Preserve both sides of a conflict and prior states; do not silently use last upload wins. No CRDT, server, or sync provider is selected by this contract.

## Current implementation and gaps

The current product is a local macOS SwiftUI/AppKit prototype. ScreenplayDomain contains Foundation-based model code and the editor uses a native text view. The Mac ScreenplayViewModel still combines creative commands, persistence, AppKit dialogs, PDF work, and presentation state. iPadOS, iOS, browser clients, robust cross-device sync, package-level persistence, and notarized distribution are not implemented merely because this architecture is adopted.

The existing Specs/open-screenplay-1.0.schema.json describes the monolithic prototype representation. It is not the schema for the revised package draft. Preserve compatibility until a loss-aware migration exists.

The 120-page development-build benchmark measured model edit/autosave at 12–17 ms and repagination at approximately 128–169 ms. These are single-workload engine timings, not UI latency targets or proof of touch responsiveness. Full native editing and rendering need measurement before declaring long-script responsiveness acceptable.

## Delivery sequence

1. Measure native long-script editing and workspace switching; address the measured pagination/rendering bottleneck while preserving printed output.
2. For the next creative editing change, extract its command and reference/undo transaction from the Mac view model behind a platform-independent API. Expand incrementally; avoid a speculative full rewrite.
3. Specify and test the portable package and complete-project companion relationship, unknown-data preservation, transactions, and migration.
4. Prototype one serious iPad writing/shot workflow against the same command layer. Evaluate touch, hardware keyboard, selection, offline save, and recovery before selecting more presentation reuse.
5. Add version-aware sync, separate media transfer, focused phone workflows, and complementary web access through explicit later milestones.
6. Validate signing/notarization and platform distribution requirements before distribution claims. The current local bundle is a development build.

## Acceptance evidence

For each UI change, verify the affected native interaction, keyboard/focus behavior, selection/context continuity, supported window sizes, and accessibility. For creative mutations, test identities, references, Undo/Redo, and persistence. For storage or sync, test failure, offline behavior, conflict preservation, and recovery. Record measured performance with workload, build configuration, and limitations; do not substitute model timings for complete UI timings.

A framework change requires a documented comparison covering editor quality, Mac behavior, iPad interaction, offline storage, sync, media, timeline performance, distribution, and maintainability. Fast prototyping or maximum UI sharing alone is not a sufficient reason.
