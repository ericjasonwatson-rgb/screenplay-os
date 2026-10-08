# Phase A prerequisite: legacy data-loss guard

2026-10-08. Optional beat/scene duration targets remain unimplemented. Inspecting
storage before adding those fields exposed a prerequisite safety gap; this
increment fixes that gap without changing the document schema or script layout.

## Changes

- `Sources/ScreenplayDomain/LegacyRoundTrip.swift:10`: scope the `post_enabled`
  migration exception to `ai_settings.post_enabled`, not any field with that name.
- `Sources/ScreenplayDomain/LegacyRoundTrip.swift:16`: failed comparison protects
  the original instead of reporting no loss. Unknown null, false, empty string,
  array and object fields are included in dropped paths.
- `Sources/ScreenplayDomain/LegacyRoundTrip.swift:39`: differing array lengths are
  reported conservatively rather than skipping the entire array and its unknown
  fields. This may open normalized legacy data as a copy even when normalization
  was harmless. It is safer than assuming unsupported content was preserved.
- `Tests/ScreenplayEditorTests/AuditFixTests.swift:83`: extend unknown-field tests
  to null/empty values, array length changes, scoped migration and failed parsing.
  Disposable application-level fixtures verify that editing a protected copy does
  not rewrite the source bytes.

This is a source-protection guard, **not** general lossless JSON round-tripping.
The editable copy still contains only supported model fields; original bytes stay
in the source file. Identity-aware preservation and number-preserving raw JSON
storage remain requirements before declaring broader schema evolution safe.
No new schema version or target-duration model is introduced here.

## Verification

Automated tests use disposable files. No new manual UI pass, installed application
replacement, packaging or release is included. Phase A remains partial: duration
targets, additional Final Draft comparisons and full phase acceptance are pending.

Both `./Scripts/test.sh` and
`SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh` passed: 265 Swift
tests in 45 suites, 37 Python checks and 14 self-tests, **316 per configuration**.
Logs: `/tmp/phase-a-guard-debug.log` and `/tmp/phase-a-guard-release.log`.

Typing benchmark before/after uses baseline `536d9a8`, the same disposable
`/tmp/screenplay-audit-long.json` (106 pages, 2,112 elements), SHA-256
`9d95d6036beed93a2c0b95a51bc92d427aa76ef47db6a5338b9ef64fb73cb428`.
Command: `SCREENPLAYOS_BENCHMARK_POSITION=middle SCREENPLAYOS_BENCHMARK_NAVIGATOR=1
SCREENPLAYOS_BENCHMARK_CONTEXT=1 SCREENPLAYOS_BENCHMARK_ITERATIONS=20
./Scripts/benchmark-typing.sh /tmp/screenplay-audit-long.json`.
Logs: `/tmp/phase-a-guard-before.log`, `/tmp/phase-a-guard-after.log`.

| Configuration | Before median | After median | Before first edit | After first edit |
| --- | ---: | ---: | ---: | ---: |
| Debug | 84.76 ms | 83.41 ms | 229.68 ms | 222.33 ms |
| Release | 55.89 ms | 56.17 ms | 174.06 ms | 204.09 ms |

These are single paired harness runs, not measured key-to-screen latency. The
guard runs at document load, not on each keystroke. No material median regression
was observed; these results do not establish a typing-performance improvement.
