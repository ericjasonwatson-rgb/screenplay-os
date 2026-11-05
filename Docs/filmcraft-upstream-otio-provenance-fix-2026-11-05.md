# FilmCraft v0.17.1 — preserving external OTIO clip provenance

Status: upstream implementation proposal and reproducible failing test, **not** a merged FilmCraft patch. Prepared for ScreenplayOS's draft PR #9; no changes to FilmCraft itself.

## Reproduced problem

ScreenplayOS emits standard `Clip.2` items with a keyed
`media_references["DEFAULT_MEDIA"]` map and `metadata.screenplayos`
containing canonical occurrence, scene, shot, board and Take UUIDs,
generation-job ID and SHA-256 fingerprints. The official OpenTimelineIO
0.18.1 parser round-trips this data successfully.

Pinned FilmCraft CLI 0.17.1 imports and re-exports the same synthetic
document, but the returned Clip has no `metadata.screenplayos`.
The independent comparator correctly refuses to associate that clip
with the source Take. [Failing CI run](https://github.com/ericjasonwatson-rgb/screenplay-os/actions/runs/42065575647).

## Evidence in FilmCraft's tagged source

In `storytold/filmcraft` **tag `v0.17.1`**:

- [`crates/interchange/src/otio.rs`](https://github.com/storytold/filmcraft/blob/v0.17.1/crates/interchange/src/otio.rs):
  `fc(v)` retrieves only `v["metadata"]["filmcraft"]`.
- `Imp::clip` calls `let meta = fc(c).cloned()` and passes that
  into `apply_clip_meta`. It never stores `metadata.screenplayos`.
- `Exp::item_json` constructs a new clip metadata object from
  FilmCraft's own fields, under the `filmcraft` namespace.
- [`crates/project/src/track.rs`](https://github.com/storytold/filmcraft/blob/v0.17.1/crates/project/src/track.rs):
  `TrackItem` persists fields used by FilmCraft, but no generic
  preservation slot for arbitrary OTIO clip metadata.

This is a source-level explanation for the observed loss, not evidence
of how every future FilmCraft release behaves.

## Recommended upstream fix

1. Add an optional, bounded `otio_external_metadata` object to
   FilmCraft's canonical `TrackItem`. Use `#[serde(default)]` for
   backwards-compatible loading of existing FilmCraft projects.
   Preserve namespaces **other than** `filmcraft`, never overriding
   FilmCraft's own runtime metadata. Limit serialized size and depth.
2. On OTIO import, copy the external clip namespaces from
   `c["metadata"]` into the new project field after validating that
   the object has the expected type. Do not treat third-party
   metadata as executable instructions or user-visible trusted state.
3. On OTIO export, merge those stored namespaces into the clip
   metadata object alongside newly generated `filmcraft` fields.
   If a namespace conflict occurs, fail explicitly or apply a
   documented non-destructive policy; never silently replace
   provenance.
4. Define behavior when an editor duplicates, splits, groups,
   replaces or nests a clip. Preserving the **same occurrence UUID**
   on two copies creates a duplicate ID and must fail ScreenplayOS's
   import gate. FilmCraft should either invalidate the external
   occurrence binding on a new clip or mark its identity status
   explicitly, rather than silently cloning it as authoritative.
5. Test save/reopen of the native FilmCraft project before re-export,
   not only in-memory interchange. That ensures provenance is stored
   durably, not merely held in a transient importer variable.
6. Preserve timeline duration, source-in, media path, and notes while
   editing. A changed path or trim may be a review proposal, but
   original media SHA and prompt/job provenance must remain
   attributable to the original Take.

## Required acceptance test

Use the synthetic two-appearance Take timeline emitted by
`ProductionTakeEditorialBridgeTests` (no private film assets).

1. Import the synthetic `.otio` through the pinned FilmCraft CLI,
   save/reopen the native FilmCraft project, then export OTIO.
2. Parse both files with official OpenTimelineIO, verify all eight
   `TRACKED` fields per occurrence, verify exactly two distinct
   occurrence IDs, one shared Take ID and one shared generation job.
3. Reorder or trim one clip: its unchanged identity/provenance must
   survive, and changed timing must be reported as review-only.
4. Duplicate one occurrence: the returned provenance must not
   falsely claim both are the *same original occurrence*. Explicitly
   decline seamless round-trip if the duplicate has no trusted binding.
5. Remove media or drop provenance: fail closed, preserve the
   original ScreenplayOS document and report missing information.
6. Exercise the public-safe adversarial gate:
   `Scripts/test_filmcraft_roundtrip_review.py`.

Until FilmCraft supplies that behavior and passes a new pinned build,
ScreenplayOS may offer only **manual, non-authoritative relink
candidates**. No editor results can be applied automatically.
