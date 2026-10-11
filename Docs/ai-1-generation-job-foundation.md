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

## Next increment

Add an actor-isolated ledger controller and explicit state transitions. Relaunch
recovery must leave ambiguous running/queued paid requests paused for inspection;
it must never resend them automatically. Then add an exact consent preview and a
local exportable activity record before connecting any live provider adapter.
