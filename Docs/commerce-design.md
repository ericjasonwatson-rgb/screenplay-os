# Commerce design

Status: Stripe Managed Payments selected by the owner on 2026-10-11. A Stripe sandbox exists; no live product, price, webhook, production signing key, checkout, or sale exists. Commerce enforcement remains off.

## Decision and boundary

Stripe is merchant of record for covered transactions. Checkout is hosted by Stripe Checkout or Payment Links and opens in the user's browser. ScreenplayOS never embeds payment UI, receives card data, or contains Stripe credentials.

This is an operational choice, not a permanent application dependency. `PaymentProvider` isolates hosted checkout and subscription-management URLs. The app trusts only a ScreenplayOS Ed25519 signature, never a Stripe response, so Paddle or another merchant can replace Stripe without changing offline license verification.

| Concern | Stripe Managed Payments | Paddle replacement |
|---|---|---|
| Seller role | Stripe/Link is merchant of record for covered transactions | Paddle is merchant of record |
| Checkout | Hosted Checkout or Payment Links only | Hosted Paddle checkout |
| Subscriptions | Stripe Billing lifecycle events | Paddle Billing lifecycle events |
| License delivery | ScreenplayOS webhook Worker and Ed25519 license | Same Worker contract behind a Paddle adapter |
| Payouts | Standard Stripe payout timing after activation | Monthly payout cycle |
| App coupling | `PaymentProvider` URL adapter only | Replacement adapter; license format stays unchanged |

Sources checked 2026-10-11: Stripe [Managed Payments](https://stripe.com/managed-payments), [pricing](https://support.stripe.com/questions/managed-payments-pricing?locale=en-GB), [Checkout subscription management](https://docs.stripe.com/payments/checkout/limit-subscriptions), and [Billing portal configuration](https://docs.stripe.com/api/customer_portal/configurations/create); Paddle [pricing](https://www.paddle.com/pricing) and [payout timing](https://www.paddle.com/help/manage/get-paid/when-and-how-do-i-get-paid). Recheck terms before live activation.

## Fulfillment and activation

1. The app asks `PaymentProvider` for a browser URL and opens Stripe Checkout or a Payment Link.
2. A verified Stripe webhook reaches `LicenseWorker/`. It accepts `checkout.session.completed`, `invoice.paid`, `customer.subscription.updated`, and `customer.subscription.deleted`; verifies the raw-body Stripe signature; validates plan, status, paid period and seats; and records event ids for idempotency.
3. The Worker creates or updates an entitlement and stores only commerce/license metadata. It never receives screenplay text, media, prompts, or AI credentials.
4. The Worker emails a six-digit, 15-minute, one-time activation code to the Stripe receipt email. ScreenplayOS sends only the normalized email and code to the Worker and receives the signed license. Unknown-email requests return the same response to prevent account discovery.
5. The signed payload contains email, plan, tier, seats, paid-period end, final expiry (period end plus 14 days), and license id. The app embeds only the public key and verifies offline.
6. Renewal events replace the entitlement used for the next activation. Cancellation stops future renewal; the current license remains usable through its signed final expiry. License failure never blocks free-core project access.

`LicenseActivationClient` is the app-side HTTP boundary. It uses an ephemeral URL session and exchanges JSON only with the ScreenplayOS Worker. It contains no Stripe SDK, API key, webhook secret, or signing key. File import remains available as a recovery path until activation UI is accepted.

## Managed Payments subscription management

Stripe's Managed Payments page says buyers manage purchases, subscriptions, payment methods, and support through their **Link account**. Stripe's general Billing docs describe the separate Customer Portal, but the Managed Payments documentation reviewed on 2026-10-11 does not promise that ordinary Billing Customer Portal sessions are the supported Managed Payments route. Do not build against that assumption.

Preferred route: use the Link management destination exposed in the Managed Payments receipt/account experience when Stripe provides a stable supported URL. Until that has been validated with a sandbox subscription, `PaymentProvider.subscriptionManagementURL` stays optional. Fallback: show `hello@screenplayos.com` with a prefilled cancellation subject; support schedules cancellation at period end in Stripe, records the request, and lets the resulting subscription webhook update the entitlement. The app must never claim cancellation succeeded merely because it opened email.

## Security and production gates

`swift run screenplay-license-tool` creates test licenses. Pass a private-key path outside the repository. The real private key belongs in the Worker secret store/HSM with restricted signer access, rotation, backup and recovery. Never place it on the website, in `SignupWorker/`, in the app bundle, or in Git. `LicenseWorker/` accepts the PKCS#8 private key only through `LICENSE_PRIVATE_KEY_PKCS8_BASE64`; tests generate disposable keys.

Production prerequisites: approve refund/cancellation language; verify Beaver Point LLC; create live products only after owner approval; deploy and threat-model the Worker; configure durable storage and transactional email; create the production signing key outside Git and back it up; replace the placeholder public key; test replay, renewal, dunning, refund and cancellation; keep `commerce.enforcement` off until acceptance passes.
