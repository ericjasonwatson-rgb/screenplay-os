# Free core and open projects: architecture audit

2026-09-12. Inspected the existing macOS prototype against the supplied Free Core · Open Projects · Local Authoring · Connected Cloud amendment. This is an implementation audit, not a claim of format conformance or completed cloud capabilities.

## Findings: the ten repository questions

| Question | Observed implementation and consequence |
|---|---|
| 1. Where is canonical data? | `Sources/ScreenplayDomain/ScreenplayDocument.swift` defines `OpenScreenplayDocument`, project, screenplay elements, outline, shots, boards, editorial sequences/beats/clips, notes, proposals, and activity. This Foundation-only target contains no UI framework or account SDK. `Specs/open-screenplay-1.0.schema.json` documents the legacy monolithic representation. |
| 2. Is UI state mixed in? | Selection, panes, focus, zoom, search, and playback position live in `ScreenplayViewModel`; recent paths use local preferences. Persisted `AISettings` toggles and `ProductionContext.contextEnabled` mix project preferences with authored content. Preserve those legacy fields now; classify/migrate preferences explicitly when designing the successor format. Workflow statuses called “selected” are not the same as current UI selection. |
| 3. Are identities stable? | Project, screenplay elements, shots, boards, sequences, and beats have UUIDs. Scene relationships also use legacy `S001`-style spine IDs, retained through reorder but allocated from the currently present set: deletion can allow reuse and independent devices can allocate the same value. There is no object revision/causal model. Edit guide rebuilding previously regenerated clip UUIDs even for surviving sources; the narrow correction below fixes that case. This does not make identities sync-ready. |
| 4. Is persistence local-first? | Yes for the current prototype: local files, synchronous autosave, local undo/recovery/snapshots, with no network/account prerequisite. `DocumentFileWriter` prevents first-save overwrite and compares exact prior bytes before atomic replacement. The comparison and replacement are not one atomic compare-and-swap; concurrent writers can still race. Existing save feedback describes local state, not cloud backup. No sync or remote-backup state machine exists. |
| 5. Are types unnecessarily UI-bound? | The domain is Foundation-only. The Mac `ScreenplayViewModel` combines creative commands, reference repair, undo, persistence, dialogs, PDF, and presentation. It imports AppKit/SwiftUI and is not a reusable cross-client command layer. Some helpers, including file writing and page layout, are independent of UI. Extract commands only as bounded features require them. |
| 6. Account/entitlement dependency? | None found in the core or current writing path. There are no Free/Studio/Cloud project types. Current account-free operation is compatible with the amendment; future commercial cancellation behavior is a contract, not a tested billing implementation. |
| 7. External-service assumptions? | No current provider/network client was found in application/domain sources. AI workflow/proposal vocabulary exists, but the context assistant runs local synchronous heuristics. Its user-invoked operation can directly create production notes/entities with undo and attribution; it is not an asynchronous candidate/adoption system. Proposal targets lack input revisions. Future remote generation must not reuse this direct-mutation path as its completion handler. |
| 8. Can the representation evolve? | Yes, as a starting point, not as an already compliant portable package. The existing decoder uses closed keys, drops unknown fields, decodes a version string without a compatibility gate, and normalizes scene/editorial data on load. The revised `.screenplay` package draft requires unknown-data preservation, explicit migrations, safe version handling, and package transactions that are not implemented. Loading alone does not rewrite source bytes, but a later save serializes the normalized model. FDX is interchange, not canonical storage. |
| 9. Are media references separated? | Large media blobs are not embedded in the present model. Boards currently hold descriptions, prompts, timing, and source references. A stable media registry, local/cloud/proxy/offline locations, and recovery of unavailable assets do not exist. `productionMedia` and `generatedVideo` enum cases do not constitute media support. |
| 10. Minimum change now? | Adopt the amendment in governing instructions and the implementation contract; preserve existing compatible boundaries; fix UUID churn for surviving generated Edit clips and test it. Leave accounts, sync, media, reviews, revision schemas, and command-layer reconstruction for explicit milestones. |

## Changes made

- Preserved the supplied amendment verbatim as `free-core-open-projects-amendment.md` and made it required reading in `AGENTS.md`.
- Reconciled the platform contract: free account-optional local operations, one project format across tiers, independent services/entitlements, three persistence states, review-first browser participation, version-scoped sharing, explicit AI adoption/content egress, separate media locations, and mobile deferral. Updated its performance reference to the existing same-harness Release/Debug evidence.
- Fixed generated Edit clip identity in `EditorialSpine.syncEditReferences`: a surviving board or shot placeholder in the same beat retains its UUID across rebuilds, source renumbering/renaming, timing changes, and save/reopen. A genuinely new source gets a new occurrence ID. The file schema and current timing derivation are unchanged.
- Added three regression tests for shot reorder/rename/repeated reopen, board timing/reorder/reopen, and source replacement versus survivor identity.

## Deliberately deferred

No accounts, billing, entitlements implementation, networking, sync, cloud backup, hosted review, browser/mobile client, media hosting, AI orchestration, permissions, analytics, pricing, or open-source licensing decision. No broad view-model extraction, project migration, service stubs, or rewrite of user documents.

Published Review Version is now a documented contract only: an immutable/versioned projection of a specific project revision, with scoped object/time references and owner-authorized guest access. There is no working publisher or sharing endpoint.

## Tests and limits

`SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh` passed: 72 Swift Testing entries plus 14 self-tests. One Swift Testing entry is the opt-in typing profiler and returns without benchmarking when no fixture is supplied; this run therefore exercised 85 functional tests, including the three new identity regressions. No typing benchmark was rerun for this change.

The tests cover the current supported model and editor safeguards. They do not prove cloud conflict handling, unknown-field preservation, migration, real media replacement, or subscription downgrade behavior. No UI was changed or manually revalidated in this amendment pass. The earlier live-app relaunch timeout remains unresolved; passing tests do not establish that the user's running app has relaunched successfully.

## Remaining risks and release gates

1. **Forward compatibility/data preservation:** unknown fields are discarded and newer format versions are not gated. Implement loss-aware reading/migration before releasing a successor format or claiming open-format conformance. Never test migrations against the user's only copy.
2. **Editorial continuity:** this fix preserves IDs only for surviving generated clips of the same source kind within a beat. The guide still reconstructs timing, source offsets, notes, ordering, and source-kind transitions from shots/boards; it is not an independently authored edit timeline. Media substitution, multiple occurrences of one source, cross-beat moves, and stable shot-to-board replacement require explicit semantics before those features ship.
3. **Scene/revision identity:** reconcile legacy spine strings with permanent scene identity, prevent reuse, and define revision ancestry before cross-device reconciliation or externally durable review references.
4. **Persistence/concurrency:** synchronous whole-document saves can affect typing; byte comparison has a concurrent-writer race. Do not present it as sync or distributed conflict resolution.
5. **Service boundaries:** persisted project preferences and local assistant direct adoption require deliberate separation when real service work begins. No external call may silently upload content or adopt stale output.
6. **Live app verification:** the previous relaunch failure needs a separate native launch investigation; it is not corrected by this amendment.

## Single next architectural decision

**Define the successor canonical project revision envelope and its loss-aware relationship to the independent `.screenplay` package.** Decide where the complete project's authored data/revision identity lives and how existing monolithic documents migrate without loss, while preserving an independently recoverable screenplay subset. This is one storage/interoperability decision, not a reason to choose a cloud vendor or build collaboration now. It must precede published review versions and cross-device sync; current writing improvements can continue without waiting for those services.
