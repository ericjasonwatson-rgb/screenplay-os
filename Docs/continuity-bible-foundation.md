# Continuity bible foundation

Status: Phase AI-2 foundation implemented in `ScreenplayDomain`; review UI and project-package persistence remain pending.

`ContinuityExtractor` runs locally and reads the canonical screenplay without changing it. It proposes:

- character entries from character cues after removing trailing cue extensions such as `(V.O.)`, `(O.S.)`, and `(CONT'D)`;
- location entries from common `INT.`, `EXT.`, combined, and `I/E.` headings after separating time of day;
- conservative recurring-prop candidates from repeated all-caps phrases in action elements.

Every proposal carries exact source text, element identity and order, and the current scene heading. Occurrence count and first appearance are derived from that evidence. Prop extraction intentionally favors missed candidates over false positives; ordinary prose cannot be reliably reduced to nouns without language analysis.

The versioned `ContinuityBibleLedger` keeps proposals separate from adopted entries. Extraction alone writes nothing to the bible. Adoption creates an entry linked to its source elements and returns an undo token; undo removes that entry and restores the proposal. Character entries default to `fictional` and must be deliberately reclassified before any future real-performer workflow.

This slice does not add provider calls, AI alias merging, reference generation, consent records, prompt composition, takes, or media storage. Those require the review workflow and package-persistence boundary first. Tests use local deterministic data only.
