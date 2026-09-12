# Legacy project migration plan

**Status:** DRAFT FOR IMPLEMENTATION — no converter or new save format has shipped.
**Decision:** `project-format-decision.md`. Applies to the actual legacy monolithic JSON structure, not merely a filename or a `1.0` label.

## Read-only planning first

Read original bytes through a duplicate-key-detecting, number-preserving JSON parser. Inventory every field, type, identity, reference, and unknown subtree before creating typed projections. Do not use `OpenScreenplayDocument.init(from:)`: it currently normalizes scene identities and regenerates editorial structure while decoding.

A migration plan records source SHA-256, source byte count, detected dialect, proposed target versions, mapping version, identity map, per-field disposition, unresolved references, and warnings/blockers. Identity assignments belong to the plan and are reused on retries for that exact source digest. Changed source bytes invalidate the plan. Missing metadata must be reported as missing; do not invent authors, creation dates, IDs that purport to be historical, or object revision ancestry.

Every source field receives one disposition: mapped, preserved opaque, explicitly transformed, or blocked. Retaining original bytes is a backstop, not proof that active fields migrated correctly. Unmapped creative data prevents a “lossless migration” claim even when an archival copy exists.

## Field mapping

| Legacy source | Target and rule |
|---|---|
| `format`, `format_version` | Preserve source declarations in provenance; detect legacy shape independently. Target core/extension versions are explicit conversion results. Unsupported dialects block conversion. |
| `project.id`, `project.screenplay_id`, `screenplay.id` | Preserve ProjectID and DocumentID. Mismatched linkage or duplicate IDs block automatic conversion. Missing IDs require a reported new assignment, never replacement of a valid existing ID. |
| `project.metadata`, `screenplay.metadata`, `title_page` | Catalog metadata to manifest, authored title-page wording to screenplay. Preserve divergent/extra metadata explicitly; never overwrite one with another without a documented mapping. |
| `screenplay.elements` | Preserve UUID, exact Unicode text, blank elements, embedded line breaks, order, type strings, external IDs, and revision marks. Unknown types use neutral display and remain intact. |
| Scene heading `spine_id` | Allocate a distinct permanent scene UUID once per heading in the migration plan. Map an unambiguous legacy spine string to that UUID and retain the original alias. Duplicate/missing aliases with dependent references require explicit repair; do not guess from text or scene number. |
| Source links, outline scene links, note anchors | Preserve element IDs; translate scene aliases through the same map. Unresolved historical links remain explicit unresolved references with their original value. Never attach them to another live scene. |
| `outline` | Film outline records with existing beat IDs, order, wording, and scene links. |
| `shots` | Free `shots.json`, preserving shot UUIDs, canonical array order, wording, notes, status, setup, and source links through documented fields/extensions. Preserve contradictory legacy numbering as metadata and report the discrepancy. Scene addendum UUIDs are assigned once in the plan. Orphan shots remain recoverable; do not discard them to satisfy grouping. |
| `script_notes` | Core note UUID/body/anchor/resolved state; preserve timestamps and legacy scene alias in documented metadata. |
| `production_context` | Film production records with existing IDs, notes, entities, status and provenance. Do not infer user-authored versus generated intent from wording. Preserve `context_enabled` as a legacy preference outside canonical creative records. |
| `ai_settings` | Preserve in the legacy-preferences extension during conversion, marked noncreative and never interpreted as entitlements. Future account/session preferences remain outside the package. |
| `proposals`, `activity` | Preserve full content, IDs, status, targets and attribution. Do not fabricate input revision history for old proposals. Legacy activity is private project content, not analytics. |
| `board_frames` | Film boards with existing IDs, shot links, prompts, descriptions, duration, source refs, notes, and status. Do not invent media assets for text-only boards. |
| `editorial_spine` | Preserve raw sequence/beat/clip IDs, actual order, timing, offsets, source-kind values and notes. Do not invoke `ensureEditorialSpine`. Record that legacy generation semantics are limited; preserve supplied state rather than rebuilding it. Duplicate identities block automatic conversion. |
| `screenplay.revision`, revision settings, page locks | Preserve legacy counters/marks separately from new revision ancestry. Archive lock data unchanged in a versioned legacy extension; do not interpret Character offsets as Unicode-scalar offsets. Until lock behavior has a validated adapter, affected packages are recovery/read-only for production-locked editing and must not claim lock-conformant printing. |
| Unknown fields/files | Preserve semantic JSON and opaque bytes with original path/key association. Unsupported required semantics block editing; retaining bytes alone is not proof that editing around them is safe. |

The initial imported project revision has no invented parents. Object revisions describe the imported state; they are not a reconstruction of historical edits. Mapping new scene/addendum/revision UUIDs does not change existing creative object UUIDs.

## Conversion transaction

1. Inspect bytes without rewriting or updating recent-document preferences. Produce the plan and blockers.
2. Validate draft schemas and semantic constraints, including IDs, safe paths, ranges, links, required versions, and unknown-data retention.
3. Write only to a new destination selected through Save a Converted Copy; never replace the legacy source. Include original bytes and the migration report under provenance. This archive may contain private content and is excluded from review publication.
4. Stage the complete package, verify byte inventories, independently reopen it, and compare every mapped field against the plan. On any failure, leave the source and active document untouched.
5. Only after success switch the active document to the converted package. Keep the original source available. Autosave into the new format is enabled only after this explicit conversion flow.

A basic screenplay export may omit film data only with a clear subset/loss report. It cannot be called a complete project migration. Importing FDX remains a separate interchange operation with its own losses.

## Acceptance matrix before enabling writes

| Fixture/failure | Required evidence |
|---|---|
| Minimal/empty script, blank paragraphs, Unicode combining sequences and emoji | Exact text and order recover through an independent reader; offset units are checked explicitly |
| Unknown nested keys, types, extensions, large integers and numeric precision | No semantic value loss; duplicate keys rejected; no closed-struct round-trip |
| All current optional records | Field-by-field comparison covers notes, proposals, activity, boards, edit offsets, and production metadata |
| Reordered scenes/shots, deleted source, duplicate/missing spine aliases | Stable valid IDs, one explicit mapping, retained dangling links, ambiguity blocks automatic repair |
| Existing clip timing/order differing from generated guide | Raw authored state and identities retained without normalization |
| Production-locked legacy script | Original lock bytes/units retained; unsupported lock behavior prevents editable/print conformance claims |
| Unsupported major/core/project extension version | Read-only recovery; no overwrite or autosave conversion |
| Core-only writer changes a rich package | Stale inventory detected; text recovered and companions preserved; no false revision coherence |
| Two offline branches with/without retained base | Both preserved; missing ancestry disclosed; no timestamp winner |
| Named snapshot followed by edits and asset changes | Full named state and exact required media versions remain independently recoverable |
| Missing media, unsafe paths, symlinks, case-colliding paths | Missing optional media warns without deleting objects; unsafe/ambiguous paths are not traversed or silently overwritten |
| Failure at each stage: staging, inventory, replacement, durability, reopen | At least one complete recoverable prior/current generation; source unchanged; no false save success |
| External writer modifies base mid-save, disk full, permission loss | Conflict/failure retained as recoverable local work; no unverified overwrite |
| Free/accountless/offline operation | Core create/open/edit/save/reopen/export has no service or entitlement dependency |

These are planned tests, not passing results. Package-level atomicity, schemas for every payload, the independent reader, default layout profile, specification license, and production-lock adapter remain release gates. Do not enable migration based solely on this document.

## Next implementation slice

Implement the read-only legacy inspector and report first, with synthetic fixtures for duplicate keys, unknown data/large numbers, version detection, ambiguous scene aliases, and raw editorial preservation. It must leave fixture bytes unchanged. Do not expose a new save format in the UI until preservation, conversion, recovery, and failure tests pass.

## Read-only inspector implementation — 2026-09-12

`Scripts/inspect-legacy.py` now implements the initial risk inventory using a raw, duplicate-key-detecting JSON reader with exact numeric tokens. See `legacy-inspector.md` for scope and usage. It reports source digest/size, known and unknown field paths, identities, reference risks, and raw editorial presence without converting or assigning identities. Full schema validation, target field mapping, a reusable identity-assignment plan, and all package writer gates remain unfinished.

## Preservation and initial field mapping — 2026-09-12

`--mapping` now validates complete source reconstruction from in-memory field fragments and structural records. Core text/catalog fields have explicit routes; richer records remain explicitly preserved as legacy extension fragments. See `legacy-field-mapping.md` for implemented rules, tests, and limitations. This is not a completed target schema, active migration of every feature, identity-assignment plan, or converted-copy writer.
