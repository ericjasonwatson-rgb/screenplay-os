import test from 'node:test';
import assert from 'node:assert/strict';
import worker, {StripeManagedPaymentsProvider} from '../worker/index.mjs';

class MemoryKV {
  constructor() { this.values = new Map(); }
  async get(key) { return this.values.get(key) ?? null; }
  async put(key, value) { this.values.set(key, value); }
  async delete(key) { this.values.delete(key); }
}

async function keys() {
  const pair = await crypto.subtle.generateKey({name: 'Ed25519'}, true, ['sign', 'verify']);
  const privateBytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  return {pair, privateBase64: Buffer.from(privateBytes).toString('base64')};
}

async function signature(body, secret, timestamp = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  const bytes = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${body}`));
  return `t=${timestamp},v1=${Buffer.from(bytes).toString('hex')}`;
}

function webhookEvent(id = 'evt_1', type = 'invoice.paid') {
  const periodEnd = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
  return {id, type, data: {object: {
    customer_email: 'writer@example.com', subscription: 'sub_1', status: 'active',
    metadata: {screenplayos_plan: 'pro-monthly', screenplayos_tier: 'pro', screenplayos_seats: '1'},
    lines: {data: [{period: {end: periodEnd}}]}
  }}};
}

test('provider exposes only allowlisted hosted checkout URLs', () => {
  const provider = new StripeManagedPaymentsProvider({
    STRIPE_CHECKOUT_PRO_MONTHLY: 'https://checkout.stripe.com/test-link',
    STRIPE_CHECKOUT_PRO_ANNUAL: 'https://evil.example/checkout'
  });
  assert.equal(provider.checkoutURL('pro-monthly').hostname, 'checkout.stripe.com');
  assert.equal(provider.checkoutURL('pro-annual'), null);
});

test('signed webhook is idempotent and sends an activation code', async () => {
  const kv = new MemoryKV();
  const sent = [];
  const env = {LICENSE_STATE: kv, STRIPE_WEBHOOK_SECRET: 'whsec_test', ACTIVATION_EMAIL: {send: async value => sent.push(value)}};
  const body = JSON.stringify(webhookEvent());
  const request = () => new Request('https://license.screenplayos.com/webhooks/stripe', {method: 'POST', headers: {'Stripe-Signature': awaitableSignature, 'Content-Type': 'application/json'}, body});
  const awaitableSignature = await signature(body, env.STRIPE_WEBHOOK_SECRET);
  assert.equal((await worker.fetch(request(), env)).status, 200);
  assert.equal(sent.length, 1);
  assert.equal(JSON.parse(await (await worker.fetch(request(), env)).text()).duplicate, true);
  assert.equal(sent.length, 1);
});

test('invalid webhook signature is rejected before storage', async () => {
  const kv = new MemoryKV();
  const response = await worker.fetch(new Request('https://license.screenplayos.com/webhooks/stripe', {method: 'POST', headers: {'Stripe-Signature': 't=1,v1=bad'}, body: '{}'}), {LICENSE_STATE: kv, STRIPE_WEBHOOK_SECRET: 'x'});
  assert.equal(response.status, 400);
  assert.equal(kv.values.size, 0);
});

test('subscription deletion resolves the receipt email without putting it in the event', async () => {
  const kv = new MemoryKV();
  const env = {LICENSE_STATE: kv, STRIPE_WEBHOOK_SECRET: 'whsec_test', ACTIVATION_EMAIL: {send: async () => {}}};
  const paidBody = JSON.stringify(webhookEvent('evt_paid'));
  await worker.fetch(new Request('https://license.screenplayos.com/webhooks/stripe', {method: 'POST', headers: {'Stripe-Signature': await signature(paidBody, env.STRIPE_WEBHOOK_SECRET)}, body: paidBody}), env);
  const deletion = webhookEvent('evt_deleted', 'customer.subscription.deleted');
  delete deletion.data.object.customer_email;
  deletion.data.object.id = 'sub_1';
  deletion.data.object.status = 'canceled';
  delete deletion.data.object.subscription;
  const deletedBody = JSON.stringify(deletion);
  const result = await worker.fetch(new Request('https://license.screenplayos.com/webhooks/stripe', {method: 'POST', headers: {'Stripe-Signature': await signature(deletedBody, env.STRIPE_WEBHOOK_SECRET)}, body: deletedBody}), env);
  assert.equal(result.status, 200);
  assert.equal(JSON.parse(await kv.get('entitlement:writer@example.com')).active, false);
});

test('one-time activation returns an Ed25519-verifiable license with final grace expiry', async () => {
  const kv = new MemoryKV();
  let delivered;
  const generated = await keys();
  const env = {LICENSE_STATE: kv, STRIPE_WEBHOOK_SECRET: 'whsec_test', LICENSE_PRIVATE_KEY_PKCS8_BASE64: generated.privateBase64, ACTIVATION_EMAIL: {send: async value => { delivered = value; }}};
  const body = JSON.stringify(webhookEvent('evt_activation'));
  await worker.fetch(new Request('https://license.screenplayos.com/webhooks/stripe', {method: 'POST', headers: {'Stripe-Signature': await signature(body, env.STRIPE_WEBHOOK_SECRET)}, body}), env);
  const exchange = () => worker.fetch(new Request('https://license.screenplayos.com/activation/exchange', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({email: 'writer@example.com', code: delivered.code})}), env);
  const first = await exchange();
  assert.equal(first.status, 200);
  const license = await first.json();
  assert.equal(license.payload.email, 'writer@example.com');
  assert.equal(license.payload.planID, 'pro-monthly');
  assert.equal((Date.parse(license.payload.expiresAt) - Date.parse(license.payload.paidThrough)) / 86_400_000, 14);
  assert.equal(await crypto.subtle.verify('Ed25519', generated.pair.publicKey, Buffer.from(license.signature, 'base64'), new TextEncoder().encode(JSON.stringify(license.payload, Object.keys(license.payload).sort()))), true);
  assert.equal((await exchange()).status, 403);
});

test('activation request does not reveal whether an address has an entitlement', async () => {
  const env = {LICENSE_STATE: new MemoryKV()};
  const response = await worker.fetch(new Request('https://license.screenplayos.com/activation/request', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({email: 'unknown@example.com'})}), env);
  assert.equal(response.status, 204);
});
