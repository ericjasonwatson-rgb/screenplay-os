# AI connections

Status: local model and router foundation implemented 2026-10-10. Connection
settings UI, Keychain migration execution, guided setup, OAuth, organization-file
import and production adapters are not implemented.

## Local model

`AIConnection` records a stable ID, connection kind, service identity, auth method,
capabilities, cached model descriptions, connection status, dates, optional spending
notes and a Keychain reference. It has no credential field. The catalog validates
unique identities, capability/model consistency, defaults and optional integer-micro
monthly budgets.

Capabilities are text, image, video, voice and music. Connection kinds are aggregator,
direct provider, organization and managed. `managed` reserves compatibility with the
later relay design; it does not enable a server or account requirement.

`AIConnectionRouter` selects only connected records with the requested capability.
It honors an organization-required route before a user choice or default, validates
the chosen model against the connection and policy, and returns explicit missing
capability, unavailable connection/model or policy-blocked failures. It performs no
network or Keychain work.

## Existing OpenAI and Anthropic state

The current dialogue UI stores keys under Keychain service
`dev.screenplayos.ai-provider`, with account `openai` or `anthropic`, and stores the
selected model in local preferences. `LegacyDialogueConnectionMigration` creates a
new metadata record that references that existing item as
`legacy-dialogue:<provider>`. It does not read or copy the secret. The migrated
record is `needs_attention` until a later mocked/tested migration coordinator verifies
the model and connection. Runtime migration has not been enabled.

Validation passed in Debug and Release on 2026-10-10: 311 Swift tests in 54
suites, 37 importer checks and 14 self-tests in each configuration. Connection
tests are deterministic and make no network or Keychain calls.

## Organization policy

`AIOrganizationPolicy` is the typed content planned for a `.screenplayos-org` JSON
file: organization name, allowed services/models, per-seat budget, required routes
and a Keychain credential reference. Validation rejects empty identity, invalid
budget/currency and model rules for disallowed services. The typed record cannot
contain a plaintext credential. File import, signature/trust, admin authoring and
secure credential delivery remain unimplemented; email or chat must not be presented
as a secure key-distribution system.

## Provider status

No aggregator is supported by this increment. OpenRouter, fal.ai and Replicate are
research candidates from the product brief. Their current OAuth/PKCE availability,
third-party-app terms, model-list APIs, pricing data and credential rules must be
verified from official sources immediately before adapter work. Absence of verified
third-party OAuth means pasted-key setup, not a scraped or reverse-engineered login.

Existing direct transports remain the previously implemented OpenAI/Anthropic text
assist and OpenAI image assist. They have not yet migrated to the catalog/router or
durable generation-job path. The free core remains independent of this catalog.

## Next executable slice

Add an injectable local catalog store and credential-store protocol, then implement
a one-time migration coordinator that leaves existing Keychain bytes in place. Test
read/write/delete with an in-memory credential store. Only then expose Settings > AI
Connections and guided setup. OAuth and adapters remain separate, provider-verified
increments.
