# Destination schemas and scene/reference mapping

**Status:** Implemented, in-memory legacy migration candidate profile `0.1`. Not a released Open Screenplay standard, package writer, or app save mode.

```sh
python3 Scripts/inspect-legacy.py /absolute/path/to/project.open-screenplay.json --candidate
```

The command reports source identity, allocated scene identities, reference mappings, and validated payload names. It emits no screenplay payload values and writes no files. Blocked candidates return exit 1 with a finding; unreadable input or a missing dependency returns exit 2. Input bytes are checked again after construction. This is a change detector, not an exclusive file lock.

## Schema and dependencies

`Specs/drafts/legacy-destination-0.1.schema.json` is a JSON Schema 2020-12 bundle with local definitions for the currently migrated legacy payloads: manifest, screenplay, notes, shots, outline, boards, edit, production records, proposals, activity, project envelope, and legacy extension archive. It is checked and evaluated by `jsonschema`, using a separate Decimal validation view so the preserved numeric tokens are untouched. UUID and timestamp checks are enabled explicitly. The timestamp implementation rejects invalid dates, missing offsets, and leap seconds; the last is a conservative restriction of this candidate profile.

`Scripts/requirements-inspector.txt` pins the tested dependency. Basic inspection and `--mapping` remain standard-library-only. `--candidate` and the destination tests require `jsonschema==4.26.0`, already available in the current development environment. There are no remote schema references or network requests.

The bundle permits unknown fields and open workflow/type strings for preservation. Its existing-record schemas intentionally retain several legacy field names. It is an executable migration profile, not complete conformance schemas for all future Open Screenplay files, media, formatting ranges, or production locks. Missing optional source collections do not manufacture optional destination files.

## Identity and active transformations

Scene UUIDs derive deterministically from ProjectID, the mapping namespace, and the existing heading element UUID. Their identity therefore survives heading text edits and reordering; their legacy `S001` alias does not determine identity. Existing element, project, shot, note, board, sequence, beat, and clip UUIDs are retained. New scene/addendum IDs are collision-checked against known creative IDs. Unknown extension `id` fields are not treated as creative objects.

Each known scene reference must resolve to exactly one source heading. The candidate adds `scene_id` or `linked_scene_ids` while retaining legacy aliases. Missing/ambiguous scene or UUID references block candidate generation rather than being reattached. Source inspection and the earlier preservation layer remain available to recover such files without repair. Existing destination-named fields that could be overwritten also block conversion for explicit reconciliation.

Active transformations are:

| Legacy data | Candidate payload |
|---|---|
| Project catalog metadata and screenplay UUID | Complete core manifest |
| Elements, exact text/order, title page, unknown element fields | Screenplay payload with added scene UUIDs |
| Script-note body/source/status | Note text, element anchor, resolved flag; IDs and other metadata retained |
| Shots and source links | Scene addenda, stable shot IDs, element references, one-based ordinal in existing per-scene array order; legacy numbering retained |
| Outline links, board links, editorial scene links | Film records referencing the same scene UUIDs |
| Edit sequences, clips, offsets, timing, notes | Copied without the app's normalization/regeneration path |
| Production records, proposals, activity | Separate film payloads retaining records and attribution |
| Unknown data, legacy preferences, screenplay revision settings and production locks | Immutable migration archive in a versioned legacy extension |

Shot range offsets are retained as legacy fields, not falsely relabeled as Unicode-scalar ranges. Shot setup is retained rather than guessed to be a camera framing description. Source lock baselines and offsets are archived unchanged; this candidate cannot promise lock-aware editing or print behavior. Unsupported source note resolution states block rather than invent a resolution flag.

## Revision envelope and checks

The initial project envelope identifies the project/screenplay, a new candidate revision, current known-object revision IDs, and exact byte sizes/SHA-256 values for the encoded candidate payloads. Its creation timestamp describes candidate construction; parent lists are empty, so source revision history is not fabricated. The envelope excludes itself from its file hashes. The legacy archive records the hash of the original input bytes; its own encoded bytes have a separate file-inventory hash.

This is initial snapshot metadata, not an implemented revision engine. Collection revision semantics, tombstones, merge ancestry, retention, media versions, and published review versions remain future work. Regenerating a candidate at a different construction time creates a different project revision while keeping scene identity stable.

`validate_candidate` checks the source digest, payload schemas, and the complete deterministic transformation against the original source using the candidate's construction timestamp. This catches incorrect content/references even if somebody recomputes file hashes after changing them. The archive is a recovery backstop, not the evidence that active transformations are correct: tests separately inspect mapped IDs, references, note state, shot numbering, and edit timing. The archive has no live editing authority and must be excluded from future scoped review uploads.

Candidates retain `conversion_ready: false`. No serialized candidate-import interface, file writer, save transaction, account requirement, or app integration was added.

## Verification

27 focused inspector/mapping/destination tests pass, including nine destination tests. Coverage includes minimal/empty documents, cross-view scene/shot references, stable scene IDs after reorder/rename, ambiguity and target-field collisions, high-precision unknown values, UUID/date/type rejection, stale/tampered candidates, populated edit trims and production-lock archival, and read-only CLI behavior with blocked diagnostics. CLI tests verify unchanged input bytes and modification times and no new input-directory files.

The next implementation gate is a staged converted-copy writer with independent readback and fault-injection tests. It must keep the original untouched and must not enable production-locked editing or declare complete format conformance merely because this profile validates. The existing native app continues saving its current format.

## Converted-copy writer follow-up — 2026-09-12

A separate experimental macOS writer now creates only new destinations, retains exact source bytes, performs exclusive publication, and verifies staged/published output. See `legacy-converted-copy.md` for failure/recovery behavior and 37 focused tests. The app still cannot edit the new package format; existing save behavior and the remaining conformance gates are unchanged.
