# Lemon Squeezy setup for ScreenplayOS — superseded

Superseded on 2026-10-11 by the Stripe Managed Payments decision in `commerce-design.md`. Retained as a historical comparison only. Do not create products, credentials, webhooks, or accounts from this checklist.

## Account and store

1. Create the account at `https://app.lemonsqueezy.com/register`. Use an owner-controlled Beaver Point LLC email and enable two-factor authentication.
2. Create one store named **ScreenplayOS**. Choose a stable subdomain; the hosted storefront can remain disabled because `screenplayos.com` will link directly to checkout later.
3. Keep the store in **Test mode**. Product data created there does not automatically exist in Live mode, although Lemon Squeezy supports copying products later.
4. Do not create an API key or webhook secret until the receiving service exists. Never paste either into the app, website source, GitHub, email, or this document.
5. Store activation is a separate owner action. Lemon Squeezy requires a business questionnaire and identity/business verification before live sales. Complete it using Beaver Point LLC's correct legal and tax information; consult the company's accountant for W-9 classification.

## Test products

Create one subscription product named **ScreenplayOS** with these test-mode variants:

| Variant | Billing | Price | Seats | Notes |
|---|---:|---:|---:|---|
| Pro Monthly | Monthly | $12 | 1 | User supplies AI-provider accounts |
| Pro Annual | Annual | $99 | 1 | Standard annual plan |
| Founding Pro Annual | Annual | $69 | 1 | Keep unlisted; eligibility process is not finalized |
| Studio Monthly | Monthly | **TBD** | 3 minimum | Do not publish until price and seat rules are approved |
| Studio Annual | Annual | **TBD** | 3 minimum | Do not publish until price and seat rules are approved |

Enable Lemon Squeezy license keys for test variants only as a receipt/fulfillment identifier. They are not the app's authorization proof; the future webhook service exchanges a verified purchase event for a ScreenplayOS-signed offline license.

Do not upload a release artifact yet. The existing direct, notarized DMG pipeline remains authoritative. Later, checkout fulfillment should provide a short-lived link or redirect to a license-delivery page plus the verified current download.

## Information to record outside Git

- Test store ID.
- Test product ID.
- Each test variant ID.
- Test webhook signing secret, after a receiver exists.
- Test API key, only if the receiver needs API reconciliation.
- Owner, finance and support contacts.

Store identifiers are not secrets, but keep them in the deployment configuration rather than scattering them through source. Secrets belong in the selected host's protected secret store.

## Stop conditions

Stop before activation, live-mode products, real payment tests, API-key creation, webhook creation, checkout links on the public website, or license enforcement. Those steps require a tested receiver, production key custody, approved legal/refund language, and a manual app acceptance pass.
