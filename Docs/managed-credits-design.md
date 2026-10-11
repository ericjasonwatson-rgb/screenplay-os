# Managed credits design

Status: design only. No server, account system, payment integration, credit balance,
managed connection or relay is implemented.

## User promise

BYOK remains the default and requires no ScreenplayOS account. A managed connection
is an optional convenience for users who deliberately buy ScreenplayOS credits.
Before its first send, show: **“Easiest. Requests go through ScreenplayOS servers.”**
The consent preview must still identify the provider/model, exact content and cost.

## Relay boundary

The app authenticates a credit user and sends one frozen generation-job request to
an authenticated relay. The relay authorizes the account and balance, converts the
request to the selected provider adapter, and streams request bytes to that provider
and response bytes back to the app. Prompt, screenplay, reference-media and output
bodies are not written to application logs, traces, queues, analytics or durable
storage. Request bodies use bounded memory or encrypted ephemeral spool storage that
is deleted on completion/failure; which mechanism is feasible is an open engineering
decision and must be load-tested.

Durable server billing metadata is limited to account ID, opaque app job ID,
provider/model, capability, timestamps, terminal status, provider charge, customer
charge, currency, refund amount and idempotency key. It excludes project names,
object IDs meaningful outside the app, prompts, media, outputs and provider
credentials. Operational metrics use aggregate counts/latency without content.
Access to billing metadata is role-limited and audited; retention duration remains
an owner/legal decision.

“Zero retention” applies to creative content, not the minimum transaction records
needed for billing, fraud, refunds and tax/accounting. Marketing must not collapse
those two claims.

## Accounts, purchases and ledger

Only managed-credit users need an account. BYOK features do not check account state.
Credit packs may be $10, $25 and $50, but those amounts are examples until margin,
fees, taxes, refunds and provider terms are approved. The checkout provider owns
payment-card handling. A signed webhook credits an append-only server ledger; the
client never grants itself balance.

Every debit uses an idempotency key bound to the app job ID and records estimated
cost before send and settled cost after the provider response. The app mirrors
confirmed transactions into its local cost ledger. Server balance is authoritative
for purchased credits; local project data remains authoritative for creative work.
Concurrent requests reserve estimated cost so the balance cannot be overspent.

Provider price changes update a versioned rate table. The consent preview freezes a
quote with a short expiry. An expired or materially changed quote requires renewed
consent. Never silently charge above the approved amount.

## Failure, refunds and fraud

No provider submission means release the reservation. A provider-declared failed
job receives an automatic credit reversal unless the provider charged a nonrefundable
amount; that case needs explicit policy and disclosure. Partial/usable output,
cancel-after-submit and timeout-with-unknown-provider-state require provider-specific
settlement rules. Support can issue ledger adjustments but cannot rewrite history.

Chargebacks freeze only managed-credit spending, not local projects or BYOK. Apply
rate limits, verified email, purchase velocity rules and payment-provider fraud tools.
Do not inspect creative content for ordinary fraud review. Abuse and legally required
content controls must be defined per provider and jurisdiction before launch.

## Provider and legal gate

Before contracting or coding the relay, confirm in writing for every provider:

- resale, sublicensing and multi-tenant relay rights;
- whether end-user identity or consent must be passed through;
- content-moderation and abuse-reporting duties;
- data use, retention, training and subprocessors;
- geographic, age and restricted-use rules;
- pricing, failed-job charges, rate limits and notice of changes;
- use of output and disclosure requirements.

Public API availability does not grant resale rights. A provider that prohibits
relaying or resale cannot back managed credits.

## Privacy-policy draft

> If you choose Managed Credits, ScreenplayOS sends the content shown in the request
> preview to ScreenplayOS systems so we can relay it to the AI provider you selected.
> This may include screenplay text, prompts, reference images, audio, or video. We do
> not retain that creative content after the request finishes, and we do not use it
> to train models. We retain limited transaction records—your account, provider and
> model, time, status, and cost—to operate billing, refunds, security, and required
> financial records. The selected AI provider processes your content under the terms
> disclosed before you send. You can use your own provider connection instead; BYOK
> requests go directly from the app to that provider and do not pass through
> ScreenplayOS systems.

Legal counsel must revise this against the deployed infrastructure, provider terms,
retention schedule and jurisdictions. It is a product draft, not a current policy.

## App integration

Managed service metadata uses `AIConnection(kind: .managed)` and the same capability
router, exact-consent preview, durable job state, cost ledger and candidate/Take
adoption path as BYOK. Feature code must not branch on payment architecture. The
adapter exchanges an account token for relay access; it never stores provider keys
in the project.

## Owner decisions before implementation

1. Whether managed credits are strategically worth becoming a billing intermediary.
2. Payment provider, countries, currencies, taxes and minimum purchase.
3. Stated margin and whether price includes payment fees and taxes.
4. Creative-content ephemeral-spool design and maximum request size/duration.
5. Billing-metadata retention and support/audit access.
6. Refund rules for partial output, cancellation and provider-charged failures.
7. Providers with written relay/resale permission.
8. Moderation, abuse escalation, sanctions and age policy.
9. Account recovery, deletion and export requirements.
10. Whether the privacy wording and “zero retention” claim survive legal review.
