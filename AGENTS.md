# ScreenplayOS project instructions

Before modifying UI, application architecture, persistence, or platform support, read:

- Docs/platform-architecture.md
- Docs/platform-implementation-contract.md
- Docs/ui-ux-design-constitution.md
- Docs/product-architecture.md

For native-format or storage changes, also read Docs/open-screenplay-format-1.0-revised-draft.md. It is a draft contract, not the implemented schema. Specs/open-screenplay-1.0.schema.json is the legacy prototype schema; preserve existing documents until a tested migration exists.

Build professional local-first filmmaking software: one canonical project model, shared creative commands, and platform-specific interfaces. macOS is the full professional reference; iPad is a first-class creative target; iPhone is a focused companion; web is complementary. Do not constrain the project model to browser APIs or stretch one identical UI across devices.

Preserve the five coordinated views (Outline, Script, Shot, Boards, Edit), object identities, selection context, native editing quality, and safe persistence. Keep platform UI, entitlements, sync transport, and large media storage separate from canonical authored data. Shared UI code must not compromise screenwriting quality.

Use the implementation contract's current-gap statements and acceptance criteria. Do not claim unimplemented platform, sync, storage-format, or distribution capabilities. Changes to these docs alone are not runtime implementation.
