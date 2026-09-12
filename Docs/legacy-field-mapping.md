# Validated legacy field mapping and preservation

**Status:** Implemented in-memory foundation, not a package converter or complete target schema implementation.

Run the existing read-only inspector with `--mapping`:

```sh
python3 Scripts/inspect-legacy.py /absolute/path/to/project.open-screenplay.json --mapping
```

This builds field fragments in memory, validates their coverage and preservation, and prints mapping metadata. It never writes a converted package. Creative payload values are omitted from CLI output; field paths/keys and identity metadata remain visible. Files are reread to detect changes during inspection and mapping. This does not lock the file against future changes.

## Implemented boundary

`preserve_json` encodes the raw JSON tree without coercing numeric tokens into floating point or strings. It retains exact Unicode, numeric lexemes (including negative zero and exponents), Boolean/null types, array order, and empty containers. Object key order and whitespace may change. Invalid numeric tokens, floats, non-string keys, and invalid Unicode are rejected rather than approximated.

`create_mapping` rejects inspector blockers before generating candidate fragments. Supported input yields:

- Source SHA-256 and byte count, mapping version, and intended unreleased target versions.
- Structural records for every nonempty object/array, retaining keys and array lengths.
- One explicit mapping for each scalar or empty container, with source pointer, value type, disposition, and destination pointer/file role.
- In-memory fragments containing each preserved value, with no full source backup subtree required for recovery.
- No generated identities, no fabricated history, and `conversion_ready: false`.

The destination file names identify draft ownership. Fragments are dictionaries of destination JSON Pointers to values, **not complete JSON files ready to place in a package**. For example, the project fragment does not yet contain a revision envelope, and the manifest fragment does not yet derive its document ID. Writing these fragments as package files would be invalid.

## Current routing policy

| Source | Draft destination | Disposition |
|---|---|---|
| Legacy format/version declarations | Manifest fields | Value mapped; declaration alone does not establish package conformance |
| Project ID and screenplay link | Project identity fields | Mapped |
| Project catalog title/author/timestamps | Manifest catalog fields | Mapped |
| Screenplay ID, empty element array, element IDs/types/text in source order | Screenplay fields | Mapped |
| Recognized authored title-page strings | Screenplay title page | Mapped |
| All other fields, including unknown content, legacy aliases, locks, revision marks, shots, boards, edit records, notes, and service preferences | Legacy extension fragments keyed by original JSON Pointer | Preserved opaque; target feature mapping remains incomplete |
| Nonempty object/array shape | Recovery structural records | Preserved opaque as reconstruction metadata |

Unknown subtrees are not treated as understood merely because they contain familiar field names. A nested unknown `id` or `text` does not become canonical identity or screenplay text. JSON Pointer escaping distinguishes `/`, `~`, array indexes, and object keys. Empty arrays and objects retain their different types.

This first policy deliberately preserves richer fields until their active target schemas and transformation rules exist. Opaque preservation is not equivalent to implementing those features or completing a lossless project migration. Production-lock offsets are never reinterpreted, and editorial sequence order, clip identities, timing, offsets, and notes are never regenerated.

## Validation and recovery

`recover_mapping` reconstructs the complete legacy tree using only structural records and mapped/opaque fragments. `validate_mapping` then checks that:

1. Source digest, size, mapping version, and non-converting status match.
2. Every destination obeys the supported routing policy; no duplicate source/target or unaccounted fragment exists.
3. Every structural record is reachable and every original value/empty container is recoverable.
4. Reconstructed source values and structure agree with the original, comparing a type-preserving encoding rather than Python's loose numeric/string equality.
5. Encoding and reparsing the recovered tree retain the exact numeric tokens and semantic content.

A changed source, missing mapping, wrong route, changed value/type, reordered array, extra fragment, or unreachable structural record fails validation. Validation is an in-memory API; serialized-plan import/replay, guarded editing patches, package schema conformance, scene UUID assignment, and output transactions are not implemented. The original file remains the source of truth.

## Verification and next gate

The test command includes 18 inspector/mapping tests, ten added for this layer. They cover precision-preserving serialization, unknown/empty data, reconstruction without original bytes, stale/unsupported plans, tampered mappings/values/types/order, blocked input, populated editorial data and locks, and CLI read-only behavior. Input bytes, modification time, and directory contents remain unchanged in CLI tests.

Next, define and validate the actual core/extension payload schemas and implement the remaining active field transformations, with scene-identity and reference mapping. Only after that should a staged converted-copy writer be added and tested for interruption, outside edits, disk failure, and recovery. Current app saves and user documents are unchanged.

## Destination candidate follow-up — 2026-09-12

The executable destination profile and scene/reference transformations are now implemented in memory. See `legacy-destination-candidate.md` for payload coverage, nine new destination tests, conservative blockers, and remaining format/writer limitations. `--candidate` validates complete payload objects for currently migrated legacy records; package writes and app migration remain disabled.
