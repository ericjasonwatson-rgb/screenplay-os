# Campaign brief, bid basis and change review

Status: native macOS draft implementation with local agency-text and DOCX evidence. Manual UI acceptance remains required; exact CI evidence belongs to the PR head.
This is a bounded extension to the existing filmmaking document, not a new primary
workspace, client portal, accounting system, or AI document-reconciliation service.

## Use

Open a legacy filmmaking project, then **Campaign > Campaign Brief & Scope…**.
The experimental writing-only package editor is not supported.

1. Enter the brand, objective, audience, key message and mandatory requirements.
2. Add deliverables with duration, aspect ratio, market and language. Expand Shot
   coverage to link the existing canonical shot IDs used by each version.
3. Record bid assumptions and manual document/version/page references. Optionally
   import agency UTF-8 text or supported DOCX through Agency Sources, review it, then cite inclusive
   line ranges against a deliverable or assumption. See the workflow below.
4. Freeze a named baseline. Brand, objective and at least one named deliverable
   with an aspect ratio are required. A baseline is a snapshot, **not approval**.
5. Close the panel, revise the actual script, shots or boards, then reopen it.
   Compare with a selected baseline to see exact before/after source changes,
   affected deliverables and unresolved links. Go to Source returns to the existing
   workspace and stable object. Deleted sources remain visible in the report.
6. Record evidence of separately received creative, production-approach or spend
   approval. Each record binds one exact baseline; stale/unresolved baselines
   cannot receive new approvals. A spend record requires a ceiling and currency.
   These records do not verify identity, create signatures, authorize provider
   requests, make payments, or carry approval forward to a revised scope.
7. Export a local change-review text file for producer review. No sending/sharing
   occurs. No automatic costing, quote or schedule promise is generated.

Draft edits are committed locally before becoming the published in-memory state.
Undo Draft Change restores prior draft content without deleting frozen baselines
or historical decisions. Closing/reopening retains saved data. A write failure
leaves the prior saved value active and shows an error, rather than silently
accepting an unsaved change. Text entry is synchronous local persistence in this
first slice; long-ledger typing latency remains a manual/performance release gate.

## Storage and portability boundary

The versioned, project-ID-bound JSON companion is under Application Support /
ScreenplayOS / Campaigns / project UUID / campaign-v1.json. It is **not included**
in screenplay saves, converted copies or portable-project exports. Ordinary Save
As preserves project identity and therefore uses the same campaign record on this
Mac. Duplicate-as-new-work semantics are not added by this increment.

Use **Private Backup…** to save the full campaign ledger separately, including
baseline text/source snapshots and approval evidence. This backup is confidential
working material, not a client-ready publication. Restore Backup accepts the same
project ID only and is available only before a local campaign exists; it cannot
replace existing history. Backups do not include screenplay/media restoration.
No existing document bytes, schema, format version, or migration behavior changes.

The store rejects malformed JSON, duplicate keys, unsupported versions/fields,
wrong-project data, oversized files and symlink paths. An unsupported file opens
as protected/read-only and is never reset. Writes use owner-only staging files,
fsync, atomic replacement, a cooperating-writer lock and an exact-byte lease.
An already changed disk copy blocks a write. This is not cross-device sync or a
security boundary against malicious same-user filesystem races. Parent-directory
symlink validation is preflight, not a descriptor-rooted sandbox. Directory fsync
is attempted after the atomic commit but has no claimed full crash-durability
proof. Readback/fault-injection and real disk-full testing remain release gates.

## Source and approval boundaries

Domain commands use Foundation and CryptoKit, with no platform UI or network dependency. Captured sources cover exact screenplay
text/style/order, shot intent/source references, board intent/order/timing and
selected image identity/hash metadata. Local media paths and generation costs are
excluded. Actual image bytes are **not rehashed**, and unselected image versions,
edit occurrences/audio, original agency PDF/deck content and document formatting are not compared.
Imported UTF-8 text and bounded DOCX body extraction are tracked as exact evidence;
DOCX originals are retained separately for human review.
Missing selected images/shot/script links are warnings that block new approval.
Legacy ranged source references also require review and block new approval because
their offset unit is not established; existing whole-element links are supported.
A referenced media file changing behind unchanged metadata is outside this slice.

Impact uses the union of baseline/current shot relationships. A shared shot change
can affect multiple deliverables. Brief and bid-assumption edits conservatively
flag the whole deliverable family. Unlinked script changes still appear and
require a producer to assess coverage. There is no inferred production-day/cost
calculation and no claim of exhaustive semantic scope reconciliation.

Frozen records are immutable through the application API, not cryptographically
signed or tamper-evident. Historical local decisions remain historical after the
working scope changes. Approval type, person and evidence are explicit; recording
a creative decision never creates spend authority. No client/agency sharing,
accounts, permissions, telemetry, AI egress or working-budget/margin fields exist.
The blank text fields can still contain confidential user-entered material; all
exports must be inspected before any later sharing.

## Integration and verification

Branch starts from main f995ee1. New campaign domain/app/test files are isolated.
The only hooks are a Published presentation flag and a Campaign menu/sheet in the
existing Mac app. It carries exactly the existing chrome compiler-expression fix
from 642f44e (also in PRs #3/#4) rather than changing other workstreams. It does not
stack on, modify or merge the image-generation branches.

The final CI configuration runs full Debug and Release `Scripts/test.sh --no-parallel`
on macOS 15, including Python LegacyInspector, Node LicenseWorker, all Swift tests,
the domain self-test and two inspector fixtures. It checks out the exact PR head,
not a synthetic merge. AppKit tests run serially because they share process-global
native state. No tests or assertions are skipped, and UI diagnostics are disabled.

A prior complete head/control run reproduced two existing native test failures on
both Campaign and pinned main f995ee1: writing-view removal after mode change and
title-preview removal after overflow. Their tests previously slept for a fixed
interval without driving the host's display cycle. The new test harness waits for
the actual hierarchy condition while servicing native layout/display and the run
loop. Original assertions remain, with added first-responder/command isolation
checks. Full-suite outcomes belong to the final PR head and CI logs; source changes
alone are not proof these failures are resolved. A fit-width roundtrip timing
failure later recurred in isolated Siri Debug: each sampled fit equation passed,
but the two wide viewport geometries differed. That test now waits for consecutive
stable geometry while servicing native commits, checks the viewport roundtrip, and
retains its original zoom tolerances and document/selection assertions. This is a
test-harness correction, not a production zoom change or a claim that all possible
rendering flakes have been eliminated.

A separate matrix composes the exact Campaign head with reviewed Siri PR3 in a new
detached worktree and runs the complete regression suite. It preserves the Campaign
sheet, blocks Siri navigation during presentations, drops blocked requests rather
than replaying stale navigation, and retains original Siri tests. Neither branch is
merged or changed by composition. See [the integration contract](campaign-siri-integration.md)
and CI manifests for both source heads and native results.

Tests cover immutable snapshots, exact Unicode and original DOCX bytes, bounded
extraction, source changes, impact union, dangling references, separate/stale
approvals, unknown JSON protection, wrong-project isolation, atomic replacement,
leases, symlinks, bounded backup reads, limits and command persistence/undo/failures.

Local Linux checks: Python LegacyInspector 42 tests, 31 passed / 11 skipped;
Node LicenseWorker 6 passed; git diff --check passed. Swift is unavailable locally. Scripts/test.sh was attempted and stopped at the
missing xcode-select command after those Python and Node checks passed.
Record final CI results in the PR; do not treat these local checks as native proof.

Before release, verify the native panel at laptop size, keyboard/text editing,
repeated add/remove, Undo after removal, Close/Escape/reopen, Go to Source,
missing sources, failed write, stale writer, backup/restore and cancellation,
and the agency import/review flows below. No live provider calls are needed.

Hosted lifecycle tests use the real Campaign sheet in an AppKit window, temporary
campaign storage and synthetic screenplay data. They exercise native text actions,
Add/Remove/Undo identity, Close/Escape/reopen, script selection and responder
isolation, project replacement, and discarded unimported agency state. A retained
SwiftUI session is bound to its ledger's project ID, not a newly supplied view-init
argument; a project change disables the old panel and dismisses it before reopening.
These tests do not launch the installed app, discover Shortcuts, drive a real file
picker or certify VoiceOver/physical-keyboard behavior. Preserve those manual gates;
passing hosted tests is not complete interactive acceptance.


## Agency text import and reconciliation

This slice imports local UTF-8 `.txt`, `.md`, `.fountain` and a bounded Word `.docx`
subset. See [Local agency document import](campaign-agency-document-import.md) for
its exact supported content, limits, original-file retention and safety boundaries.
PDF import remains disabled pending parser isolation. There is no deck rendering,
OCR, agency contact, URL fetch, inferred deliverables, screenplay rewrite or automatic
change-order pricing. Verify extracted text against the original. A filename and
hash are not proof of author, authenticity, pages or layout. Automated fixtures are
synthetic; no user agency documents or private project content are published.

1. In Agency Sources, choose a new source. A bounded native file reader accepts a
   regular local file, rejects a symlink/FIFO/directory/unsupported extension, and
   previews exact UTF-8 text or bounded DOCX extraction before anything is saved. Cancel Import or Close leaves
   the campaign unchanged. Source files are never modified.
2. Import Preview Locally saves source bytes, extracted exact text, SHA-256,
   import time, a filename without its directory path, stable document identity
   and an immutable revision identity. SHA-256 identifies bytes, not a sender.
3. Read numbered text and record a reviewer name plus a specific review note.
   Review is local evidence, **not creative approval or spending authorization**.
4. Link a reviewed inclusive source-line range to an existing deliverable or bid
   assumption, with a reconciliation note. The citation pins both source revision
   and the target's exact authored state. No target is silently rewritten.
5. Choose Revised Source for an existing document to append its next revision.
   The prior version stays available for comparison. Review does not carry forward.
   Superseded citations, changed targets and removed targets remain visible and
   block approval, even after freezing another baseline. Explicitly remove and
   recreate those citations after reconciling current source and scope.
6. Freeze a new baseline only when the reviewed scope is appropriate. Historical
   baselines retain the exact imported evidence and decisions they were frozen with.
   Undo Draft Change can restore the prior working draft, including source/citation
   state, without deleting baseline history. The undo history itself is session-local.

Line coordinates are 1-based LF/CRLF text lines, not PDF pages, screenplay element
ranges, Unicode offsets or semantic paragraphs. Terminal newline adds an empty
final line. BOM, combining sequences, CRLF and original bytes are retained. Source
hashes and stored text are revalidated on load. No Markdown/HTML is interpreted,
remote resource loaded, or embedded link followed by the source viewer.

Limits are 256 KiB extracted text per revision, 1 MiB total extracted source bytes,
2 MiB per DOCX original, 4 MiB total retained originals, 32 revisions and 256 reviews/citations each per working draft. Baselines duplicate
pinned evidence, so the existing 16 MiB ledger cap can be reached earlier with many
snapshots. Failed writes/limits leave saved state untouched; this is a bounded
prototype, not a large production document archive. Main-thread persistence and
revalidation latency require native performance acceptance before release.

The optional `agency` field is omitted for untouched old v1 campaigns, preserving
old draft, baseline and decision JSON. New builds read old campaign-v1 ledgers
without rewriting their shape. Older builds reject the new field rather than
silently discard imported evidence. This is not a screenplay-format migration.
The local campaign backup includes full source text, retained DOCX originals and historical revisions.
Reports may contain source excerpts/full text. There are no dedicated private
working-budget/margin fields, but user-imported text can contain confidential bid
or budget information: inspect every backup/report before any later sharing.
No source-import operation grants sharing, AI egress or spend authority.

Additional manual gates: cancel the picker and preview; reselect a source; switch
tabs and close with a pending preview; reopen persisted sources; review a revision;
try invalid line ranges; cite then edit/remove its target; import a revision and
reconcile old citations; Undo; navigate source warnings; compare before/after;
read long multiline/Unicode text at laptop size using keyboard and screen reader;
verify backup/restore retains exact source history. These flows are not claimed
as interactively verified by CI unit tests.
