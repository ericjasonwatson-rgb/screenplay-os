# Synthetic agency workflow corpus

All people, brands, documents, dates, approvals, money amounts and campaign details
here are fictional test data authored for this repository. No user files, agency
assets, credentials or private production documents were used. The agency and
brand names do not identify real parties or authenticate a sender.

This is a realistic *workflow scenario*, not a claim that actual Word/Office files,
visual table order, document layout, or the Campaign UI have been validated.
Actual agency sample review and native interactive acceptance remain release gates.

## Files and reproducibility

- `source/*.xml`: readable, deliberately bounded WordprocessingML body sources.
- `source/*.expected.txt`: independently authored exact UTF-8 extraction oracles.
  These have no terminal newline. Blank lines are intentional paragraph boundaries.
- `corpus.json`: generated manifest with base64 original ZIP bytes, original and
  extracted SHA-256, exact expected text/line count, and expected rejection types.
  All artifacts are text. The native tests materialize DOCX only in temporary dirs.
- `expected-lines.txt`: generated, numbered exact text, with JSON escapes exposing
  whitespace. Coordinates refer to extracted text, not Word pages or table rows.
- `Scripts/check-campaign-agency-fixtures.py`: standard-library-only generator and
  checker. Run from the repository root:

  ```sh
  python3 Scripts/check-campaign-agency-fixtures.py --check --self-test
  # Deliberately regenerate after editing the readable source/oracle files:
  python3 Scripts/check-campaign-agency-fixtures.py
  ```

The check command never rewrites fixtures. It independently reads accepted ZIP/XML, compares
body extraction to authored expected bytes, checks CRCs and deterministic archive
bytes, and verifies the checked-in manifest and line map are exact regenerated
matches. Altering any hash, text, source XML or original ZIP base64 is detected.
The generator fixes member ordering, timestamps and regular-file metadata. Method
8 uses a deterministic fixed-Huffman literal DEFLATE block, independent of zlib's
compression heuristics/version. Python `zipfile`/zlib independently decode it.
Native low-level extraction tests separately cover other DEFLATE patterns.

The checker reads regular local files only, with a 64 KiB source/member limit,
128 KiB aggregate member limit, 256 KiB archive limit and 1 MiB generated-output
limit. Its independent XML oracle rejects DTD/entity declarations, non-UTF-8
encodings, excessive depth (32) and excessive nodes (4,096) before accepting a
source. It never extracts members to disk, loads external resources, evaluates
fixture text, invokes a shell, or parses the intentionally rejected DOCX payloads
as accepted documents. Rejected originals are generated from reviewed literal
mutations; checked-in base64 is compared as bounded text, never executed. These
tooling bounds are deliberately smaller than the application's import limits.

`--self-test` runs eight standard-library safety tests without generating files.
Together with `--check` it also validates the checked-in corpus without rewriting
fixture files. File-boundary self-tests create and remove temporary files only.
The checks cover unsafe XML, byte/depth/node limits, symlinks/FIFOs/directories,
archive/member limits, unsafe paths, declared inflation excess and CRC corruption.
No source documents or remote fixtures are downloaded by either mode.

The native suite reads the manifest relative to `#filePath`, so ordinary and
Campaign/Siri detached worktrees need neither a resource bundle nor a generator
step at runtime. Python validation is not a substitute for native Swift tests.

## Accepted documents

1. `brief-v1.docx` (stored ZIP): a creative brief for the fictional Oat & Ember
   launch, with objective, audience, label/claims restrictions, deliverables, bid
   basis, supplied assets and schedule assumptions. It includes decomposed
   `Café`, an XML-escaped ampersand and an explicit line break. The one-location
   bid assumption is extracted line 18. Mandatory requirements are lines 13–14.
2. `deliverables-v1.docx` (raw DEFLATE ZIP): a six-column table with a 30-second
   16:9 hero and 15-second 9:16 social cutdown, US + UK / en-US. Each cell paragraph
   flattens separately in XML order; no visual column reconstruction is promised.
   Hero is lines 19–29 and social is lines 31–41.
3. `production-memo-v1.docx` (stored ZIP): intentionally conflicting 45-second
   hero (line 5) and two-location/travel request (line 7), revision-round limits,
   exclusions and a request for human resolution. It is not an approval.
4. `deliverables-v2.docx` (raw DEFLATE ZIP): hero changes to 45 seconds, social is
   unchanged, and a 6-second square bumper is added (lines 43–53). The revision
   note at line 57 confirms the one-studio assumption.
5. `deliverables-v2-metadata-only.docx`: the same body and exact extracted text as
   V2. Only the retained ZIP's `docProps/core.xml` revision number changes. Its
   original SHA-256 must differ; its extracted SHA-256 must remain identical.
   Imported as a revision, it still needs fresh review and citation reconciliation.

Packages also contain synthetic core properties, a minimal style and a referenced
header. The header text `FICTIONAL HEADER ONLY: not body evidence` is deliberately
absent from extracted body text; extraction notices must describe that omission.
These minimal packages are not produced, opened, rendered or certified by Office.

## Rejected documents

Each is a deterministic mutation of the synthetic creative brief. No partial
preview/import should be returned, and the original file must remain unchanged.

| Fixture | Expected native extraction failure |
| --- | --- |
| `tracked-change` | `unsupportedContent` |
| `calculated-field` | `unsupportedContent` |
| `content-control` | `unsupportedContent` |
| `alternate-content` | `unsupportedContent` |
| `tracked-change-in-header` | `unsupportedContent` |
| `external-hyperlink` (`example.invalid`, never fetched) | `externalRelationship` |
| `malformed-document-xml` | `unsafeXML` |
| `malformed-header-xml` | `unsafeXML` |
| `corrupt-document-crc` | `unsafeArchive` |
| `truncated-archive` | `unsafeArchive` |
| `trailing-archive-bytes` | `unsafeArchive` |

Tracked edits, fields, content controls, alternate representations and external
links can occur in ordinary Word files. Rejecting this bounded unsupported subset
is intentional. These cases do not imply the files are malicious, nor that all
unsupported Office features have been enumerated.

## Native scenario coverage

`Tests/ScreenplayEditorTests/CampaignAgencyScenarioTests.swift` checks:

- Real file-reader → extraction → original/text hashes → local import command →
  saved ledger/reopen. Preview alone changes neither ledger nor disk. Import does
  not rewrite authored scope or screenplay, create a baseline, review or approval.
- Contradictory documents are retained independently. Human-authored review and
  reconciliation notes explicitly retain the V1 matrix's 30-second hero and the
  one-location bid assumption over conflicting memo requests. The product does
  not detect semantic contradictions, resolve document precedence, or certify
  that the person's reconciliation is correct. An empty warning list is not a
  semantic consistency guarantee.
- A reviewed V1 baseline gets a distinct creative-only historical decision. V2
  import does not adopt 45 seconds or a bumper. The producer explicitly changes
  targets, rechecks source lines, removes stale citations and creates replacements.
  Freezing after review but before citation reconciliation still blocks approval.
- Creative, production and spend evidence remain separate and baseline-bound.
  The synthetic spend ceiling is only a local record, not payment authority,
  identity verification, a signature, costing or a provider request.
- Original V1 evidence/baselines remain immutable. Changed targets block approval.
  Undo restores saved draft content without removing frozen history or decisions.
  Reopen and in-memory backup encode/decode retain exact evidence; undo stacks are
  session-local. This is not interactive backup/export/restore acceptance.
- Metadata-only revised originals invalidate review/citations even with identical
  extracted text. Undo and reopen restore the exact prior original and history.
- Every rejection runs through the file reader against a session with existing
  reviewed work. Ledger, disk bytes, historical decisions and undo state remain
  unchanged. One subsequent undo proves no failed read added a history entry.

Run native tests on macOS with the repository's `Scripts/test.sh --no-parallel`.
A focused check can append `--filter CampaignAgencyScenarioTests`, but the full
Debug/Release and isolated-integration matrix is still required for the final head.
The Linux fixture checker does not execute Swift, AppKit, the file picker, preview
cancellation, original export, VoiceOver or Word rendering.
