# FilmCraft / ArtCraft integration verification (2026-11-05)

Status: public-source technical assessment, not a verified executable integration.

## Source and license

- ArtCraft Studio: https://github.com/storytold/artcraft — public MIT/Apache-2.0 desktop project (verify file-level notices for distribution). Primarily generative scene composition, not the NLE target.
- FilmCraft: https://github.com/storytold/filmcraft — the ArtCraft team's Rust nonlinear video editor; repository publicly documents OTIO, FCPXML, EDL, AAF and OMF interchange.
- Architecture: https://github.com/storytold/filmcraft/blob/main/docs/architecture.md — describes `file.import` and `file.exportOtio` / `file.exportInterchange` command paths.
- Parity claims: https://github.com/storytold/filmcraft/blob/main/docs/file-format-parity.md — reports internal OTIO read/write and round-trip tests, but those claims do **not** validate interoperability with ScreenplayOS.
- The services/backend repository has different licensing; do not assume permissive desktop terms apply to hosted components.

## Recommended boundary

Keep ScreenplayOS as the canonical project/story/shot/take authority, and treat FilmCraft as an optional external NLE. Start with a standalone OTIO interchange adapter; do not embed Rust UI or couple application lifecycles. Preserve IDs in a namespaced `metadata.screenplayos` object.

Before asserting compatibility:
1. Export a real two-shot, three-occurrence OTIO file from ScreenplayOS, including a repeated source shot and a deliberately missing asset.
2. Parse the output with an official OpenTimelineIO parser, then import into a pinned FilmCraft build.
3. Re-export through FilmCraft and inspect loss of canonical IDs, clip timings, asset URLs, metadata and notes.
4. Compare the returned interchange with the original snapshot; present only reviewable proposals; do not automatically mutate creative data.
5. Verify media relinking and audio separately. Do not claim embedded editing, production-ready import, or cross-editor parity based on repository documentation alone.
6. Confirm license/NOTICE handling before any code reuse or commercial redistribution.

## Existing code caveats

`MediaTimelineOTIO.export` is an experimental JSON writer. It currently uses `Clip.2` and `ExternalReference.1` schema labels and has not been validated against an official OTIO implementation. Its `source_range` and media `available_range` assume source starts at frame zero; trim/source-in and rate-aware conform remain missing. Missing media is represented by a placeholder and noncontiguous timelines are rejected.

`MediaEditReview.compare` reviews manifest snapshots, not imported OTIO files. It currently rejects added/deleted occurrences and does not implement transactional adoption or Undo. This is a deliberate safety boundary, not an end-to-end round trip.

## Decision

Proceed with read/write interchange validation and end-to-end fixtures before considering direct FilmCraft engine embedding. Preserve the Mac editor, offline free core and consent-first provider boundaries.
