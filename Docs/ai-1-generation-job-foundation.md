# AI-1 generation-job foundation

Implemented 2026-10-10. This is the first AI-1 increment. It creates the durable
record and local persistence boundary required before any new provider send; it
does not add a queue runner, UI, live request or screenplay-format migration.

## Implemented

- `GenerationJobRecord` binds a capability, provider/model, stable project and
  target UUIDs, source-revision hash, exact request snapshot, request hash, state,
  timestamps, estimated/actual costs, sanitized error and opaque provider task ID.
- `GenerationRequestSnapshot` freezes the previewed prompt, project-relative
  reference assets and string parameters. Its deterministic SHA-256 changes when
  any approved input changes.
- `GenerationJobLedger` is a versioned project-bound sidecar. Validation rejects
  unsupported versions, duplicate job IDs, cross-project records, malformed or
  changed hashes, unsafe references, bad costs and impossible state/timestamp data.
- Costs use integer micros plus a three-letter currency. Unknown remains nil and
  cannot appear as a zero-dollar estimate.
- `GenerationJobFileStore` writes sorted JSON atomically with owner-only file
  permissions, rejects non-files, symlinks and files larger than 50 MiB, then
  revalidates every record after decoding.

The ledger contains no API keys, authorization headers or provider credentials.
It is separate from the legacy screenplay JSON and from the draft open-package
schema. The caller must choose a project-bound location. This increment does not
claim that package projects or legacy documents already install that sidecar.

## Tests

`GenerationJobTests` uses fixed UUIDs, dates and MockProvider-style identifiers.
It covers stable request hashing and round trip, project binding, duplicate IDs,
consent requirements, tampered hashes, path traversal, costs, owner-only local
persistence and symlink rejection. Automated tests make no network or Keychain call.

Validation completed in both build configurations on 2026-10-10:

- Debug: 300 Swift tests in 50 suites, 37 importer checks and 14 self-tests.
- Release: 300 Swift tests in 50 suites, 37 importer checks and 14 self-tests.

All checks passed. The existing Swift concurrency, test-target and unhandled
resource warnings remain outside this increment.

## Controller increment

`GenerationJobController` now serializes state changes, validates and persists a
complete candidate ledger before exposing each accepted transition, and rejects
illegal transitions. On relaunch it derives a recovery-review set for every queued
or running job. Submission remains blocked until an explicit caller action
acknowledges that review; initialization performs no send, retry or polling work.
Running records retain their opaque provider task ID for a future deliberate poll.

Controller validation completed in both build configurations on 2026-10-10:

- Debug: 304 Swift tests in 51 suites, 37 importer checks and 14 self-tests.
- Release: 304 Swift tests in 51 suites, 37 importer checks and 14 self-tests.

All checks passed. Tests use deterministic records and perform no provider request.

## Consent and activity increment

`GenerationConsentPreview` contains the full provider, model, capability, target,
prompt, reference metadata, parameters, request hash and estimated cost (including
nil when unavailable). Consent now requires that exact immutable value to match the
current durable job. A changed field invalidates approval.

`GenerationActivityExport` is deterministic local JSON containing only jobs that
were actually submitted. It records exact creative inputs, target, provider/model,
status, timestamps and estimated/actual cost while excluding credentials and opaque
provider task IDs. Export is an explicit local write with owner-only permissions.

Consent/activity validation passed in Debug and Release: 306 Swift tests in 52
suites, 37 importer checks and 14 self-tests in each configuration.

## macOS boundary increment

The macOS app now exposes a read-only consent sheet and Activity JSON export. A
selected dialogue line can exercise the complete job path through the deterministic
offline fixture: prepare, exact preview, explicit Send, submission, completion and
local activity. The sidecar is project-ID-bound in Application Support. This proof
path does not adopt generated text and does not replace the existing live-provider
assistants.

The macOS boundary passed Debug and Release validation: 307 Swift tests in 53
suites, 37 importer checks and 14 self-tests in each configuration.

## Next increment

Add a deterministic result candidate tied to the target and revision, with explicit
undoable adoption, before routing live providers through the durable job controller.
