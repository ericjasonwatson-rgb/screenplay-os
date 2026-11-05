# Campaign brief, bid basis and change review

Status: initial native macOS implementation, draft pending native CI and manual acceptance.
This is a bounded extension to the existing filmmaking document, not a new primary
workspace, client portal, accounting system, or AI document-reconciliation service.

## Use

Open a legacy filmmaking project, then **Campaign > Campaign Brief & Scope…**.
The experimental writing-only package editor is not supported.

1. Enter the brand, objective, audience, key message and mandatory requirements.
2. Add deliverables with duration, aspect ratio, market and language. Expand Shot
   coverage to link the existing canonical shot IDs used by each version.
3. Record bid assumptions and manual document/version/page references. These are
   references for a producer to verify, not ingested or authenticated documents.
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

Domain commands are Foundation-only. Captured sources cover exact screenplay
text/style/order, shot intent/source references, board intent/order/timing and
selected image identity/hash metadata. Local media paths and generation costs are
excluded. Actual image bytes are **not rehashed**, and unselected image versions,
edit occurrences/audio, external agency decks and bid documents are not compared.
Missing selected images/shot/script links are warnings that block new approval.
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

Focused CI runs Campaign tests in Debug and Release on macOS 15. Tests cover
immutable snapshots, Codable roundtrip, exact Unicode, source changes, impact
union, dangling references, scope separation/stale approvals, validation, unknown
JSON preservation, wrong-project isolation, atomic replacement, leases, symlinks,
permissions, size limits and command persistence/undo/failures.

Local Linux checks: Python LegacyInspector 42 tests, 31 passed / 11 skipped;
Node LicenseWorker 6 passed; git diff --check passed. Swift is unavailable locally.
Record final CI results in the PR; do not treat these local checks as native proof.

Before release, verify the native panel at laptop size, keyboard/text editing,
repeated add/remove, Undo after removal, Close/Escape/reopen, Go to Source,
missing sources, failed write, stale writer, backup/restore and cancellation,
then run full Debug/Release Scripts/test.sh. No live provider calls are needed.
