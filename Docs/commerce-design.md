# Commerce design

Status: engineering design only. Commerce enforcement remains off. No merchant account, production key, checkout, webhook, or sale exists.

## Recommendation

Start with **Lemon Squeezy**. Both candidates act as merchant of record and handle sales-tax/VAT collection, refunds, chargebacks, subscriptions, and buyer receipts. Lemon Squeezy has a simpler documented fit for this launch: subscription-linked license keys, activation limits, variants for tiers/seats, downloadable files, webhooks, and twice-monthly bank/PayPal payouts. Paddle is credible for a later SaaS-heavy operation, but its documented built-in Mac licensing belongs to Paddle Classic; Paddle Billing would still require our own signed-license fulfillment service.

This is an operational recommendation, not a permanent architecture choice. The app trusts only a ScreenplayOS Ed25519 signature, never a vendor-specific response, so the merchant can change.

| Concern | Paddle | Lemon Squeezy |
|---|---|---|
| Seller role | Merchant of record; calculates and remits applicable VAT/GST/sales tax | Merchant of record; handles payments, tax, refunds, chargebacks, and PCI duties |
| Subscriptions | Paddle Billing subscriptions and webhooks | Subscription variants; active until expired after cancellation/dunning |
| License delivery | Custom webhook fulfillment for Billing; legacy license facilities are documented for Classic | Generates keys, emails them, supports activations and license API/webhooks |
| Refunds | Full or partial seller refunds; payment-method time limits | Seller policy allowed, but Lemon Squeezy may refund within 60 days to avoid chargebacks |
| Payout/accounting | Seller verification, balance/payout reports, reverse invoices | Identity verification; bank/PayPal payouts twice monthly after holding period; $50 threshold; reverse invoices |
| California LLC work | Supply Beaver Point LLC identity, EIN, bank and beneficial-owner details; reconcile payouts and income tax | Same practical onboarding and accounting work |

Sources checked 2026-10-11: Paddle help on [tax](https://www.paddle.com/help/sell/tax/how-paddle-handles-vat-on-your-behalf), [refunds](https://www.paddle.com/help/manage/your-customers/how-do-i-issue-refunds), and [statements](https://www.paddle.com/help/manage/get-paid/what-statements-will-i-receive); Lemon Squeezy docs on [merchant of record](https://docs.lemonsqueezy.com/help/payments/merchant-of-record), [licensing](https://docs.lemonsqueezy.com/help/licensing/generating-license-keys), [subscriptions](https://docs.lemonsqueezy.com/help/products/subscriptions), [refunds](https://docs.lemonsqueezy.com/help/payments/refunds-chargebacks), and [payouts](https://docs.lemonsqueezy.com/help/getting-started/getting-paid). Verify terms and fees again before account creation.

## Proposed fulfillment flow

1. Checkout is hosted by the merchant. The app never handles card data.
2. A verified webhook reaches a small ScreenplayOS license service. It checks the webhook signature, event id, product/variant id, payment state, tier, and seat count. It stores the event id before processing so retries are idempotent.
3. The service applies the pricing rules from the canonical pricing configuration, including founding eligibility and paid-month history. It creates a license payload and signs it with an Ed25519 private key held only in the service's secret manager/HSM. The repository and app contain only the public key.
4. The service sends a short-lived download link in the merchant receipt and may call the existing `SignupWorker/` welcome-email route after explicit integration work. `SignupWorker/` is currently separate and unchanged.
5. The buyer downloads the JSON license and chooses **AI > Enter License…**. A future deep link or paste flow may reduce friction, but file import is easiest to inspect and recover.
6. ScreenplayOS verifies the signature locally. Renewal can deliver a replacement file. Writing never phones home and license failure never blocks core file access.

Production prerequisites: choose merchant; approve refund policy; create products/variants; deploy webhook service; create production signing key outside Git and back it up; replace the placeholder public key; test webhook replay/refunds/cancellation; keep `commerce.enforcement` off until acceptance passes.

## License tooling and key custody

`swift run screenplay-license-tool` creates test licenses. Pass a private-key path outside the repository. Repository-local patterns are ignored only as a backstop. The real private key belongs in the production service's managed secret store, with restricted signer access, rotation and recovery procedures. Never place it on the website, in SignupWorker, in the app bundle, or in Git.

