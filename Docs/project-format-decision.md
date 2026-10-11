# ADR: one portable package with an optional film-project envelope

**Date:** 2026-09-12
**Status:** Accepted implementation direction; DRAFT FOR IMPLEMENTATION, not a released format.
**Scope:** Storage ownership, revision semantics, independent screenplay recovery, and migration boundaries. No runtime format change is made by this decision.

## Decision

Use the existing `.screenplay` package as the single portable container. Keep its required `manifest.json` and `screenplay.json` intact. Add an optional, independently versioned `project.json` envelope and optional `film/` records for richer filmmaking data. Do not introduce a separate paid project type or another live copy of screenplay text.

A minimal standalone screenplay remains valid without the envelope. When screenplayOS creates a full project, it includes the envelope even if only writing features are used. Attaching an envelope to a standalone screenplay preserves the document and element UUIDs and creates a ProjectID once. This is additive enrichment of the same package, not a subscription conversion.

The screenplay core specification and project extension have separate version declarations because they have different responsibilities. This is not two incompatible product formats. Readers declare support for each; entitlement state affects neither. The working extension identifier is `screenplayos-project`, initially `0.1-draft` during development. Do not advertise it as released 1.0.

```text
My Film.screenplay/
    manifest.json          # screenplay catalog metadata and DocumentID
    screenplay.json        # sole current screenplay text, title page, scene identities
    notes.json             # optional screenplay notes
    entities.json          # optional basic characters/locations
    shots.json             # optional canonical free shot lists and source links
    settings.json          # optional authored layout settings
    extensions.json        # optional namespaced data, including preserved legacy records
    project.json           # optional ProjectID, revision envelope, file inventory
    film/                  # optional outline, boards, edit, media index, production records
    attachments/           # optional portable media/assets; never JSON-embedded video
    versions/              # optional complete named snapshots
    provenance/            # optional migration report and original source bytes
```

Paths are illustrative until each corresponding schema is specified. The envelope and file ownership below are the chosen architecture; this ADR does not purport to supply every payload schema. Absent optional records remain absent. No account tokens, entitlement state, device bookmarks, sync cursors, or UI layout belongs here.

## Ownership and references

| Data | Single authority |
|---|---|
| Screenplay text, element order, title-page wording | `screenplay.json`; root ID equals manifest DocumentID |
| Scene UUID and heading | `scene.id` on the corresponding heading; no duplicated film scene text |
| Screenplay notes, basic entities, shots | Core optional files; film records reference their IDs |
| Outline beats and scene links | `film/outline.json`; these are authored structure, not copies of scenes |
| Boards and selected media versions | `film/boards.json` |
| Independent edit sequences and occurrences | `film/edit.json` |
| Media identity and immutable asset-version metadata | `film/media.json`; bytes in attachments or separately managed locations |
| Additional production annotations/entities, authored proposals and provenance | Documented film records or versioned extensions; never required to recover screenplay text |
| Project identity, revision lineage, file inventory | `project.json` |

Scene IDs and element IDs are separate identity domains. A heading edit/reorder preserves both. Scene creation allocates a UUID; deletion retains a tombstone in revision metadata so the identifier is never reused. Scene split/merge is an explicit command: retain the surviving scene's identity and create/retire others with recorded reference repairs. Do not infer identity from names, ordinals, filenames, or text similarity.

An EditInstanceID identifies one occurrence, not its shot or board. Multiple occurrences may reference the same source. A media substitution changes a reference while retaining occurrence ID, position, duration, notes, and narrative links. A new source that cannot satisfy the existing trim requires an explicit adjustment decision. Once an edit sequence is authored, board changes must not silently regenerate it. A derived guide must be labeled as derived and explicitly converted to authored occurrences before independent editing. This is future behavior, not a claim about today's generated guide.

## Revision envelope

The envelope contains these required fields when present:

| Field | Contract |
|---|---|
| `format`, `format_version` | Extension identifier and supported version; incompatible meaning requires a new major version |
| `project_id` | Permanent UUID, retained through ordinary Save As and relocation |
| `screenplay_id` | Existing DocumentID; must match both core manifest and screenplay |
| `head.id` | UUID identifying this exact committed logical project state |
| `head.parents` | Parent project revision UUIDs; empty for initial import, one for ordinary commits, multiple only for an explicit merge |
| `head.created_at` | Descriptive timestamp; never used to resolve conflicts |
| `head.files` | Relative file paths, byte sizes, and SHA-256 digests of the revision's current payload files |
| `head.objects` | Object kind + stable UUID + object-revision UUID + parent object revisions, and active/deleted state |

The inventory includes all current authored core/film/extension files and unknown files preserved in that current state. Exclude `project.json` itself to avoid recursive hashing, and exclude `versions/` and provenance archives from current content. Their own retention/integrity manifests govern them. Digests cover exact stored bytes, not an unspecified JSON canonicalization. JSON whitespace changes therefore require a new file digest, even when no authored object revision changes. A revision UUID is not a content hash or proof of authenticity.

Each committed project revision freezes the envelope and its payload. A changed creative object gets a new object-revision UUID; unchanged objects retain theirs. Collection order and membership are versioned objects too: element order, shot order, and sequence occurrence order must not fall between per-object revisions. Deleted objects have tombstones; Undo of a committed deletion is a new revision restoring the identity, not a rewrite of published history. In-memory undo and locally durable revision checkpoints remain separate mechanisms.

A base revision must resolve to a retained snapshot or other recoverable state before three-way reconciliation. Parent UUIDs alone are not recoverable history. If the base is missing, report missing ancestry and preserve both branches; do not invent a merge or use last-write-wins. Autosave need not retain every keystroke forever. Pruning must retain named versions, review-pinned versions, required merge bases, and their referenced assets; retention policy requires a separate tested implementation.

Project-level comparison is the conservative first conflict boundary. Object revision metadata enables later finer comparison; it does not authorize automatic semantic merging now. No network or global revision allocator is required.

## Independent recovery and older writers

Copying the core manifest, screenplay, and all present free authored optional files with their referenced attachments yields an independent screenplay package with the same DocumentID. This is an explicit subset export, not a second live authority. Report omitted film data; preserve the full original. Returning edits from that subset is an explicit compare/import operation against the originating revision, not silent synchronization.

A core-only reader can read the package without understanding `project.json`. A preserving core-only writer may retain opaque companion files while editing text. That makes the old envelope's hashes stale. A project-aware reader must detect the mismatch and treat the package as externally modified/unreconciled: recover the current text, preserve the companion records, and require reconciliation before claiming a coherent project revision or publishing review. Never blindly trust stale shot/timeline metadata, and never “repair” the mismatch by replacing the text with an old copy.

Unknown JSON is retained in an open JSON value tree beside typed projections; mutation patches understood fields by identity. Do not round-trip through today's closed Codable model. Preserve unknown numbers without precision loss, unknown strings/types/arrays, and opaque file bytes. Reject duplicate JSON keys as ambiguous. An unsupported required extension/version means read-only recovery, even if JSON parses. Unknown optional data can be edited around only when preservation and semantic independence are established; otherwise remain read-only or perform an explicitly lossy export to another destination.

## Local save and media

First implementation uses whole logical snapshots, not a delta database. Stage a complete candidate package beside the destination, validate references and inventory, and retain the prior complete generation before replacement. Publish success only after the chosen macOS persistence adapter has made the complete new generation durable under its documented guarantees. Individual JSON renames are insufficient. Platform transaction mechanics, external-writer coordination, and crash recovery must pass fault-injection tests before the writer is enabled. This ADR deliberately does not claim that a generic directory rename supplies those guarantees.

If the expected base changes, retain local edits in a separate recovery package and report a conflict. Do not overwrite a concurrently changed package. Read, validation, and migration planning never mutate the source. A later journal optimization must preserve the same portable recovery contract.

MediaID identifies the creative asset; MediaVersionID identifies immutable content. Packaged locations use safe relative paths and byte digests. Device-specific paths/bookmarks and provider credentials belong in local service state keyed by these IDs. External/cloud-only media may be unavailable, but shots, boards, and edit occurrences survive. “Portable complete copy” must gather required assets or report the exact missing assets; a metadata-only copy must not be called a complete media archive. Named versions pin the asset versions they use. Never garbage-collect unknown or snapshot-referenced files automatically.

## Review and services

A Published Review Version pins ProjectID + ProjectRevisionID plus selected object/time scopes and immutable presentation assets. It is a projection, not another editable project. Comments pin that review version. A publisher must whitelist selected scope and exclude provenance archives, private notes, unused media, and unrelated project records. Sharing one scene never means uploading the entire package by default.

Future jobs similarly pin input object revisions, with candidate outputs adopted through an explicit undoable command. Accounts, entitlements, service job queues, remote locations/credentials, and transport cursors stay outside the creative core. Nothing in this decision implements publication, synchronization, AI processing, or subscription enforcement.

## Alternatives resolved

- Separate `.film` outer container with a nested screenplay: rejected for the first implementation because it adds a second document lifecycle and complicates ordinary recovery.
- A second screenplay copy inside project data: rejected because edits could diverge.
- Everything in `screenplay.json`: rejected because core reading would become dependent on unrelated production schemas.
- Database-only or cloud-authoritative storage: rejected for the portable interchange contract. Internal performance caches can be rebuilt and must never be the only recoverable copy.

## Delivery boundary

See `project-format-migration-plan.md` for field mapping and executable acceptance work. The first implementation slice is a read-only, loss-aware legacy inspector and migration report against synthetic fixtures. It must bypass the normalizing application decoder. Next come draft schemas, independent recovery fixtures, and a staged writer with failure tests. Only then connect migration to an explicit Save a Converted Copy workflow. Existing default saves remain legacy until those gates pass.
The format identifiers were renamed from `open-screenplay` and `open-screenplay-project` to `screenplayos` and `screenplayos-project` because of a trademark conflict; readers retain permanent compatibility with the former identifiers.
