# ScreenplayOS project instructions

ScreenplayOS is a production system for AI-native filmmaking. It grew out of producing a fully AI-assisted
series, and it is built for the way film, series, and animation are now made. Writing, planning, generation,
and the edit live in one connected project: outline → script → shots → continuity bible → generation →
takes → timed animatic with audio → handoff to the edit. AI is first-class throughout, but always:
- grounded in the project: prompts are composed from the script, the shot, and the continuity bible,
  never from a blank box;
- consented: nothing leaves the Mac without an explicit, previewed send;
- provider-agnostic: the best model changes monthly, so the app routes work rather than locking in;
- accountable: every generated asset records its source, prompt, cost, and rights;
- human-directed: AI proposes, the user adopts, and adoption is undoable.
The edit-aware principle holds: every generation lands in a timed shot slot, not a loose folder.
The free core holds: writing, outlining, shots, boards from local files, and export work offline with no account.


Governing phase order: preserve and complete Phase A timing/interchange, then AI-0 through AI-6 in Docs/ai-native-production-direction.md. This supersedes the older audio/takes/handoff phase order. The owner supplied the production lessons on 2026-10-10; use Docs/ai-provider-selection-2026-10-10.md for the provisional provider order and selection criteria. Docs/storykit-architecture-proposal.md remains ON HOLD.

Before modifying UI, application architecture, persistence, or platform support, read:

- Docs/platform-architecture.md
- Docs/platform-implementation-contract.md
- Docs/free-core-open-projects-amendment.md
- Docs/ui-ux-design-constitution.md
- Docs/product-architecture.md
- Docs/ai-production-architecture.md
- Docs/ai-native-production-direction.md

For native-format or storage changes, also read Docs/open-screenplay-format-1.0-revised-draft.md, Docs/project-format-decision.md, and Docs/project-format-migration-plan.md. It is a draft contract, not the implemented schema. Specs/open-screenplay-1.0.schema.json is the legacy prototype schema; preserve existing documents until a tested migration exists.

Build professional local-first filmmaking software: one canonical project model, shared creative commands, and platform-specific interfaces. macOS is the full professional reference; iPad is a first-class creative target; iPhone is a focused companion; web is complementary. Do not constrain the project model to browser APIs or stretch one identical UI across devices.

Preserve the five coordinated views (Outline, Script, Shot, Boards, Edit), object identities, selection context, native editing quality, and safe persistence. Keep platform UI, entitlements, sync transport, and large media storage separate from canonical authored data. Shared UI code must not compromise screenwriting quality.

Use the implementation contract's current-gap statements and acceptance criteria. Do not claim unimplemented platform, sync, storage-format, or distribution capabilities. Changes to these docs alone are not runtime implementation.

Priority order: protect work and data; consent and provenance for anything sent to or received from AI; correct screenplay output and interchange (PDF, FDX); edit-aware continuity from script to generation to edit; readability; polish.
Keep changes bounded, preserve the working editor and project format, and validate
both the writing journey and connected handoffs. Final Draft parity requires
comparative testing; it is not an achieved capability. Current delivery scope is
macOS. Follow Docs/pipeline-acceptance-scenario.md for phased acceptance and evidence.
Docs/storykit-architecture-proposal.md remains ON HOLD and is not a dependency.
This direction supersedes older writing-only milestone language; free-core,
privacy, explicit AI-egress, and data-protection rules remain unchanged.

Free-core amendment: local writing, outlining, basic shots, opening, saving, reopening, and supported export must remain available without accounts, subscriptions, AI, network access, or content uploads. Maintain one portable project format across product tiers. Check entitlements at capability invocation, never to unlock owned creative data. Local save, cloud sync, and remote backup are separate states. Browser scope begins with versioned review; mobile clients remain deferred. AI features are first-class but optional. Creative-content egress requires an explicit, previewed send per request or per batch. Results are revision-bound, adopted explicitly, and undoable. Ordinary analytics never transmit screenplay text, prompts, or media. No telemetry. Tests and CI use deterministic mocks only; never live providers or credentials. Do not implement services speculatively. See Docs/free-core-architecture-audit.md for current evidence and unresolved identity/storage gaps.
