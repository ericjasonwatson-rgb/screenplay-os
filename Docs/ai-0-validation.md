# AI-0 provider boundary validation — 2026-10-10

## Changes

Governance commit `26f0c15` precedes code. AGENTS.md:3 adopts the governing
AI-native direction; Docs/ai-native-production-direction.md preserves the supplied
brief verbatim. Docs/ai-production-architecture.md distinguishes implemented,
partial and planned systems and records the remaining Phase A and owner gates.
Docs/product-architecture.md points the old phase sequence to the new one.

- Sources/ScreenplayOSApp/AIProviderCapabilities.swift:4: capability metadata,
  four service protocols, existing-provider text adapter, image conformance and
  deterministic offline mock. No jobs, model migrations or canonical format changes.
- Sources/ScreenplayOSApp/DialogueAssistant.swift:47: injected TextAssist factory
  for model listing and three-line assistance. Existing transport stays intact.
- Sources/ScreenplayOSApp/BoardImageAssistant.swift:7 and :121: explicit Sendable
  service and injectable ImageGeneration. Existing prompt/snapshot/adoption preserved.
- Tests/ScreenplayEditorTests/AIProviderCapabilityTests.swift:5: five tests cover
  all mock interfaces, deterministic fixture returns, missing media, cancellation,
  failure, truthful production capability declarations and connection injection.

## Automated checks

Before code, Debug and Release each passed 291 Swift tests in 48 suites, 37 Python
importer checks and 14 self-tests (342 per configuration). Remote main matched
`9199ee0`; the requested source tag existed remotely at
`6148474948d15c5ba5db18ab645f10acdf93a73a`. The tag was not moved.

The targeted new suite passed five tests. Final Debug and Release runs each
passed 296 Swift tests in 49 suites, 37 Python importer checks and 14 executable
self-tests: **347 checks per configuration**. Existing privacy/adoption tests continue
to exercise request serialization, stale results, Undo and board storage using
synthetic fixtures. No real key or live provider call was used. These tests do not
claim an end-to-end network-recording proof for the future AI-1–6 workflow.

The paired 106-page/2,112-element end-position benchmark used the same fixture
(`9d95d6036beed93a2c0b95a51bc92d427aa76ef47db6a5338b9ef64fb73cb428`),
hidden Navigator/Context, Focus off and 15 iterations. Timings include insertion,
layout and display requests; they are not physical key-to-screen latency.

| Configuration | Before median | After median | Before first | After first |
| --- | ---: | ---: | ---: | ---: |
| Debug | 75.29 ms | 73.88 ms | 229.94 ms | 213.50 ms |
| Release | 50.39 ms | 51.02 ms | 185.67 ms | 161.49 ms |

The small median changes do not establish a meaningful performance difference.
There is no material typing regression from the provider-boundary increment.
Logs: `/private/tmp/ai0-current-debug.log`,
`/private/tmp/ai0-current-release.log`, and
`/private/tmp/ai0-current-typing.log`.

## Manual observations

No live provider request, app installation, website release, real-performer test,
or NLE import was performed in this increment. No manual UI equivalence claim is
made. Existing native-window tests are automated checks, not manual observations.

## Assumptions and remaining work

- AI-1 and later are not started. The owner must supply the blank 1776 lessons;
  Phase A acceptance and the line-pitch decision remain gates.
- Keychain reads on MainActor, complete request/cost preview, error-fragment
  redaction, activity logging and durable provenance are documented gaps. This
  behavior-preserving increment does not claim they are fixed.
- Mock video/voice bytes are transport fixtures, not playable generated media.
  Real adapters, polling/resume, take migration and audio decoding are unimplemented.
- Existing image model entry is editable and persisted; account access is unverified.
- No new paid API/provider was chosen. Source references and verification dates
  are in AIProviderCapabilities.swift:42 and ai-production-architecture.md.
- Separate uncommitted website and icon work was not included in these commits.
