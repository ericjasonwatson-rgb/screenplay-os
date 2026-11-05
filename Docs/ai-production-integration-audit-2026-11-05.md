# AI-native production: initial integration audit (2026-11-05)

Status: source review and acceptance contract only; no runtime changes or claims of test execution.

## Evidence inspected
- `Package.swift`: Swift macOS app, domain and FDX libraries, CLI, editor tests.
- `Sources/ScreenplayDomain/ScreenplayDocument.swift`: monolithic legacy Codable project; screenplay, shots, boards, editorial spine, optional continuity bible. Its decoder supports legacy versions 1.0–1.2, not the planned lossless portable project format.
- `Docs/product-architecture.md`: five linked views; boards implemented in a bounded workflow; animatic and edit interchange partial; real-media substitution and editorial round-trip incomplete.
- `Docs/project-format-decision.md`: portable .screenplay package and film envelope are an accepted implementation direction, not released runtime behavior.
- `Docs/ai-native-production-direction.md`: AI-0–AI-6 plan, mock providers, consented content egress, provenance, take identity.
- `Docs/team-review.md`: long-script responsiveness, pagination and format fidelity remain acceptance risks.

## First implementation gate: media and edit identity

Implement a read-only, offline fixture and tests before any external editor adapter. Tests must demonstrate:

1. Two edit occurrences referencing one shot keep distinct occurrence IDs through export/import.
2. Board-to-video substitution preserves scene/shot/occurrence IDs, timing and notes; incompatible trims require review.
3. Missing media preserves metadata and produces an explicit missing-media report.
4. Relative paths reject traversal and never export private absolute paths.
5. Unknown extension fields survive losslessly or the writer refuses to mutate the original.
6. Imported editorial changes are proposals, accepted explicitly with Undo.
7. No network requests or AI provider calls are made by this interchange workflow.

## ArtCraft evaluation gate

Verify the actual source repository, license, media and timeline APIs, supported formats, and import/export behavior before selecting embedding versus interchange. Do not assume an open-source embeddable editor. Prefer OTIO/FCPXML interchange only after a fixture successfully opens in the target NLE.

## Engineering order

1. Run `./Scripts/test.sh` in Debug and Release on a Mac; record real failures and performance measurements.
2. Audit `EditInterchange.swift`, board storage, and shot/editorial identity code against the above acceptance cases.
3. Add deterministic fixture tests and a read-only export adapter on a dedicated branch.
4. Validate an external-editor round trip with real media before implementing any importer.
5. Continue AI-0 mock-provider architecture independently, without rewriting the editor.

No live generation, external content transfer, or changes to the default project writer are authorized by this audit.
