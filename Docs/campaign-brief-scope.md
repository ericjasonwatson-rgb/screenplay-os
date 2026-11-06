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
   approval. Preview the exact baseline, scope, person, evidence and any spend
   ceiling, then explicitly confirm the local record. Each record binds one exact baseline; stale/unresolved baselines
   cannot receive new approvals. A spend record requires a ceiling and currency.
   These records do not verify identity, create signatures, authorize provider
   requests, make payments, or carry approval forward to a revised scope.
7. Preview a local change-review report. The default summary lists changed source
   identities and affected deliverables without before/after source text. Opt in
   explicitly to include full evidence, inspect the exact preview, then save that
   reviewed copy. No sending/sharing, automatic costing, quote or schedule promise
   occurs.

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
working material, not a client-ready publication. **Restore Backup…** first shows
a summary of the selected file's project identity and retained records. Confirm
that review explicitly to restore. It accepts the same project ID only and is
available only before a local campaign exists; it cannot replace existing history.
Backups do not include screenplay/media restoration.
No existing document bytes, schema, format version, or migration behavior changes.

### Review and verify a private recovery copy

Backup export and **Save Retained Original…** bind the operation to the active
project and Campaign presentation. They recheck the current local ledger after
the file picker returns and before writing. A changed project, closed panel,
changed ledger or conflicting disk writer cancels the stale operation rather than
saving an unnoticed older copy. Output cannot replace the active campaign ledger
or screenplay, including resolved aliases and hardlinks. Existing destinations
are read through the bounded 16 MiB regular-file reader. The app performs no
upload; a user-selected synced folder can still sync independently.

Restore reads and validates a bounded local backup without changing storage. Its
summary identifies the project, selected filename and record counts; it is not
an authenticity check or a complete content viewer. The retained bytes can contain
private agency documents, script snapshots, notes and historical approvals. A
project ID or digest does not verify who authored or approved them. Review the
backup's origin before confirming. Restoring historical decisions does not create
new creative approval or spending authority.

Confirmation checks that the presentation and project remain active and that no
campaign has appeared either in this session or on disk. The restore write always
expects an absent ledger; it never adopts a newer lease to replace existing data.
Cancel, tab change, Close/Escape and project replacement discard pending review.
A failed write leaves prior data untouched and permits an explicit retry only
while the proposal remains valid. Success consumes the proposal. Restored
baselines, decisions, agency revisions and original DOCX bytes retain their
identities and content. JSON formatting is written in the existing canonical
campaign encoding, not preserved as arbitrary input whitespace. Session-local
draft Undo is not backed up; later edits can be undone without deleting restored
history.

These are local recovery safeguards, not cross-device sync, encryption, a signed
archive, or a complete film backup. Exported files inherit the existing file
writer's filesystem permissions and concurrency limits. Imported originals'
directory paths are not retained, so inspect the output filename before replacing
an unrelated file. Real disk-full, power-loss and installed-app recovery remain
release gates; injected failures do not establish full crash durability.

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

## Review an approval record before saving

Approval entry belongs to the selected baseline, even when two baselines contain
identical scope. Switching baselines, leaving the review tab, closing the panel or
changing projects discards unconfirmed entry. Preview is read-only: it does not
record a decision or grant authority. Check the baseline name, identity and freeze
time alongside the scope, approver, evidence and any explicit ceiling/currency.

Changing the entry or approval scope invalidates its preview. A changed baseline,
current tracked scope, source evidence or decision history also requires a fresh
preview. Confirmation revalidates the captured context before the existing atomic
save; it never silently attaches the entry to another baseline. A failed save
leaves prior records untouched and retains the proposal for an explicit retry when
its context is still current. Successful confirmation consumes that proposal.

The confirmed record is historical local evidence. **Undo Draft Change does not
erase approval records.** It does not verify the approver, create an electronic
signature, authorize a provider request or execute spending. Creative, production
and spend records remain separate and do not carry forward to revised baselines.

## Review a report before exporting

Change-review reports start in summary mode. They identify the project and frozen
baseline, count tracked changes and unresolved sources, and list affected
deliverables by name and permanent identity. Removed or renamed deliverables keep
their baseline context. A source with no linked deliverable still requires a
person to assess coverage. Summary mode omits before/after snapshots, imported
agency text, review notes and citation evidence. It does not inspect names for
confidential information and is **not automatically redacted or client-safe**.

Full evidence is an explicit option. It can contain complete script or agency
text, bid assumptions, review notes and other confidential material from the
tracked snapshots. Inspect the selectable plain-text preview before saving. The
saved UTF-8 bytes are the reviewed bytes, not a newly regenerated report. Reports
are not approval records, signatures, quotes or spending authorization.

Changing the report option or its baseline, project, project title, campaign or
tracked sources invalidates the preview. Leaving the tab or closing the panel
discards it. Saving rechecks the live context after the file picker returns;
cancelled or stale requests do not write a file. Failed writes retain a still-valid
preview for an explicit retry. Export does not modify the campaign ledger, its
history or its Undo stack. A selected destination can still be in a synced folder;
the app itself performs no upload or sharing operation.

Reports are limited to 2,000,000 UTF-8 bytes and fail rather than truncate. Choose
summary mode if full evidence exceeds that bound. Report saving rejects the live
campaign ledger and screenplay destination, including resolved aliases and
hardlinks. Existing destinations above the bounded 16 MiB reader limit are not
replaced. These preflight checks retain the shared file writer's existing limits:
they are not a lock against a malicious same-user writer changing or growing a
file between checks. Imported originals' directory paths are deliberately not
retained, so inspect the selected output filename before replacing any file.

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

Recovery tests exercise the production local file writer and absent-ledger restore
with synthetic DOCX/text revisions, explicit reconciliation, frozen baselines and
separate creative/spend evidence. The full-ledger rehearsal exports a file,
previews and restores it into a fresh storage root, reopens it, and checks exact
encoded campaign bytes, original documents, identities and later edit/Undo.
Command tests cover local history appearing inside a picker, external writers,
revocation, corrupt/wrong-project input, bounded/protected destinations and
failed-write retry. Hosted tests use native Campaign controls with injected
chooser results; they do not drive the system file panels. These are authored
acceptance cases; use the exact PR head's Mac CI result for execution evidence.


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
   block approval, even after freezing another baseline. Use **Reconcile Citation…**
   to inspect the old evidence, choose current reviewed lines and a target, then
   preview and explicitly confirm one atomic replacement. The range and target
   start blank; no mapping is inferred. A changed source, review, citation or target
   invalidates the preview. Cancel leaves the saved citation intact, and one Undo
   restores the old citation. Explicit removal remains available when a citation
   is no longer appropriate.
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
