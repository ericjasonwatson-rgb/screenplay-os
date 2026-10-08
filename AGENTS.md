# ScreenplayOS project instructions

ScreenplayOS is a narrative suite that keeps the edit in mind from the first beat:
outline → script → shot list → boards → animatic → generation or shooting → edit.
It is built for professional teams working in AI-assisted film and TV, where writer,
director, and producer are often the same few people. Every stage carries timing
and editorial intent forward. The suite hands off to dedicated tools (NLEs,
generation services, DAWs) and reads their decisions back. It does not try to
replace them.

Edit-aware everywhere: expose planned versus estimated screen time and carry
consequences downstream. Hand off through open, standard formats with stable media
references. Imported editorial decisions are reviewable proposals, never silent
script mutations. Audio is first-class in an animatic. Correct screenplay output
remains mandatory; the connected pipeline is the product's distinguishing value.

Before modifying UI, application architecture, persistence, or platform support, read:

- Docs/platform-architecture.md
- Docs/platform-implementation-contract.md
- Docs/free-core-open-projects-amendment.md
- Docs/ui-ux-design-constitution.md
- Docs/product-architecture.md

For native-format or storage changes, also read Docs/open-screenplay-format-1.0-revised-draft.md, Docs/project-format-decision.md, and Docs/project-format-migration-plan.md. It is a draft contract, not the implemented schema. Specs/open-screenplay-1.0.schema.json is the legacy prototype schema; preserve existing documents until a tested migration exists.

Build professional local-first filmmaking software: one canonical project model, shared creative commands, and platform-specific interfaces. macOS is the full professional reference; iPad is a first-class creative target; iPhone is a focused companion; web is complementary. Do not constrain the project model to browser APIs or stretch one identical UI across devices.

Preserve the five coordinated views (Outline, Script, Shot, Boards, Edit), object identities, selection context, native editing quality, and safe persistence. Keep platform UI, entitlements, sync transport, and large media storage separate from canonical authored data. Shared UI code must not compromise screenwriting quality.

Use the implementation contract's current-gap statements and acceptance criteria. Do not claim unimplemented platform, sync, storage-format, or distribution capabilities. Changes to these docs alone are not runtime implementation.

Priority order: protect work; correct screenplay output and interchange (PDF, FDX);
edit-aware pipeline continuity; readability and discoverability; visual polish.
Keep changes bounded, preserve the working editor and project format, and validate
both the writing journey and connected handoffs. Final Draft parity requires
comparative testing; it is not an achieved capability. Current delivery scope is
macOS. Follow Docs/pipeline-acceptance-scenario.md for phased acceptance and evidence.
Docs/storykit-architecture-proposal.md remains ON HOLD and is not a dependency.
This direction supersedes older writing-only milestone language; free-core,
privacy, explicit AI-egress, and data-protection rules remain unchanged.

Free-core amendment: local writing, outlining, basic shots, opening, saving, reopening, and supported export must remain available without accounts, subscriptions, AI, network access, or content uploads. Maintain one portable project format across product tiers. Check entitlements at capability invocation, never to unlock owned creative data. Local save, cloud sync, and remote backup are separate states. Browser scope begins with versioned review; mobile clients remain deferred. Future AI results require revision-bound inputs and explicit adoption; creative-content egress must be explicit, and ordinary analytics must not transmit screenplay text. Do not implement services speculatively. See Docs/free-core-architecture-audit.md for current evidence and unresolved identity/storage gaps.
