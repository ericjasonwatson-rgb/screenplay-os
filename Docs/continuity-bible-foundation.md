# Continuity bible foundation

Status: Phase AI-2 local extraction and the first macOS review workflow are implemented. Package-embedded persistence remains pending.

`ContinuityExtractor` runs locally and reads the canonical screenplay without changing it. It proposes:

- character entries from character cues after removing trailing cue extensions such as `(V.O.)`, `(O.S.)`, and `(CONT'D)`;
- location entries from common `INT.`, `EXT.`, combined, and `I/E.` headings after separating time of day;
- conservative recurring-prop candidates from repeated all-caps phrases in action elements.

Every proposal carries exact source text, element identity and order, and the current scene heading. Occurrence count and first appearance are derived from that evidence. Prop extraction intentionally favors missed candidates over false positives; ordinary prose cannot be reliably reduced to nouns without language analysis.

The versioned `ContinuityBibleLedger` keeps proposals separate from adopted entries. Extraction alone writes nothing to the bible. Adoption creates an entry linked to its source elements and returns an undo token; undo removes that entry and restores the proposal. Review also supports rejection and same-kind alias merging. Character entries default to `fictional` and must be deliberately reclassified before any future real-performer workflow.

On macOS, the **Bible** toolbar button opens an evidence-first review sheet. Each row shows its status and occurrence count; the detail pane shows the exact script lines and scene headings. Adoption can rename the entry. Merge, reject, and the sheet's review undo are explicit actions.

Accepted review state is stored atomically in a project-ID-bound Application Support sidecar. The screenplay bytes are not changed. Invalid, oversized, cross-project, and symbolic-link files fail closed. This sidecar is an interim boundary until the tested complete-project package schema can own the ledger without changing the independently recoverable screenplay core.

Adopted character entries can be classified as fictional or as a real performer. Real-performer records identify the performer or rights holder, the allowed scope (`likeness_generation`, `voice_cloning`), validity dates, optional expiry, notes, and revocation. The domain authorization gate allows fictional-character work without a performer record and fails closed for real performers unless an applicable record is active. It returns the consent-record IDs that a future generation job must freeze into provenance.

This foundation does not add provider calls, AI alias proposals, reference generation, takes, or media storage. Tests use local deterministic data only. Every future likeness or voice adapter must call the domain gate; displaying consent in the UI alone is insufficient.

The prompt composer builds deterministic requests from directing intent, the covered screenplay elements, an optional shot, and adopted Bible entries linked to those elements. The composed request freezes Bible-entry and applicable consent-record IDs into the same hashed snapshot shown at the existing Send review boundary. It does not add a provider call or authorize the older board generator to bypass the job controller. Consent must be rechecked immediately before a future live adapter submits the frozen request.
