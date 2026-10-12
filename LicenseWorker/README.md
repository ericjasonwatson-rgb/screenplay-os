# ScreenplayOS license Worker

Test-only foundation for provider-independent license fulfillment. It is not deployed and commerce enforcement stays off.

Routes:

- `POST /webhooks/stripe` verifies Stripe's signed raw body and accepts only the four documented lifecycle events.
- `POST /activation/request` sends a fresh short-lived code without revealing whether an email has a purchase.
- `POST /activation/exchange` consumes the code once and returns an Ed25519-signed license.
- `GET /checkout/:plan` redirects only to allowlisted Stripe Checkout or Payment Link hosts.
- `GET /subscription/manage` redirects to a configured Managed Payments/Link route or returns the support-email fallback.

Secrets and bindings:

- `STRIPE_WEBHOOK_SECRET`: test-mode endpoint secret.
- `STRIPE_SECRET_KEY`: optional test-mode server key used only to resolve missing subscription fields.
- `LICENSE_PRIVATE_KEY_PKCS8_BASE64`: Ed25519 PKCS#8 private key. Never put it in the app or Git.
- `LICENSE_STATE`: durable KV-compatible binding for event ids, entitlements, and one-time codes.
- `ACTIVATION_EMAIL`: transactional email adapter with `send({to, code, plan})`. It sends only purchase metadata, never screenplay content.
- `STRIPE_CHECKOUT_*`: test Checkout/Payment Link URLs. No live URLs belong in this environment.

The worker signs `email`, plan, seat count, paid-period end, final expiry (paid-period end plus 14 days), and license id. The app contains only the corresponding public key and verifies offline.

Run the worker tests through `Scripts/test.sh`; do not run a bare targeted command.
