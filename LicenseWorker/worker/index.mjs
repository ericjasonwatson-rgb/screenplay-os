const SUPPORTED_EVENTS = new Set([
  'checkout.session.completed',
  'invoice.paid',
  'customer.subscription.updated',
  'customer.subscription.deleted'
]);
const ACTIVE_STATUSES = new Set(['active', 'trialing']);
const GRACE_SECONDS = 14 * 24 * 60 * 60;
const CODE_SECONDS = 15 * 60;

const encoder = new TextEncoder();
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'}
});

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function normalizeEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

function constantTimeEqual(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function hex(bytes) { return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
function fromBase64(value) { return Uint8Array.from(atob(value), character => character.charCodeAt(0)); }
function iso(seconds) { return new Date(seconds * 1000).toISOString().replace('.000Z', 'Z'); }

async function digest(value) { return hex(await crypto.subtle.digest('SHA-256', encoder.encode(value))); }

export async function verifyStripeSignature(body, header, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!secret || !header) return false;
  const parts = Object.fromEntries(header.split(',').map(item => item.split('=', 2)));
  const timestamp = Number(parts.t);
  if (!Number.isFinite(timestamp) || Math.abs(nowSeconds - timestamp) > 300 || !parts.v1) return false;
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  const expected = hex(await crypto.subtle.sign('HMAC', key, encoder.encode(`${timestamp}.${body}`)));
  return constantTimeEqual(expected, parts.v1);
}

function eventDetails(event) {
  const object = event.data?.object || {};
  const metadata = object.metadata || {};
  const email = normalizeEmail(object.customer_details?.email || object.customer_email || object.receipt_email || metadata.email);
  const periodEnd = Number(object.current_period_end || object.lines?.data?.[0]?.period?.end || metadata.current_period_end);
  const planID = metadata.screenplayos_plan || metadata.plan_id;
  const tier = metadata.screenplayos_tier || (String(planID || '').startsWith('studio') ? 'studio' : 'pro');
  const seatCount = Math.max(1, Number(metadata.screenplayos_seats || 1));
  const subscriptionID = typeof object.subscription === 'string' ? object.subscription : object.id;
  const status = object.status || (event.type === 'invoice.paid' || event.type === 'checkout.session.completed' ? 'active' : 'unknown');
  return {email, periodEnd, planID, tier, seatCount, subscriptionID, status};
}

export class StripeManagedPaymentsProvider {
  constructor(env) { this.env = env; this.identifier = 'stripe-managed-payments'; }

  checkoutURL(plan) {
    const key = `STRIPE_CHECKOUT_${String(plan).replaceAll('-', '_').toUpperCase()}`;
    const value = this.env[key];
    if (!value) return null;
    const url = new URL(value);
    return url.protocol === 'https:' && ['checkout.stripe.com', 'buy.stripe.com'].includes(url.hostname) ? url : null;
  }

  managementURL() {
    if (!this.env.MANAGE_SUBSCRIPTION_URL) return null;
    const url = new URL(this.env.MANAGE_SUBSCRIPTION_URL);
    return url.protocol === 'https:' ? url : null;
  }

  async entitlement(event) {
    let details = eventDetails(event);
    if ((!details.periodEnd || !details.email || !details.planID) && details.subscriptionID && this.env.STRIPE_SECRET_KEY) {
      const response = await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(details.subscriptionID)}`, {
        headers: {Authorization: `Bearer ${this.env.STRIPE_SECRET_KEY}`}
      });
      if (!response.ok) throw new Error('Stripe subscription lookup failed');
      const subscription = await response.json();
      details = eventDetails({type: 'customer.subscription.updated', data: {object: {...subscription, customer_email: details.email}}});
    }
    return details;
  }
}

async function issueCode(email, entitlement, env) {
  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, '0');
  await env.LICENSE_STATE.put(`code:${email}`, JSON.stringify({hash: await digest(code), expires: Math.floor(Date.now() / 1000) + CODE_SECONDS}));
  if (env.ACTIVATION_EMAIL?.send) await env.ACTIVATION_EMAIL.send({to: email, code, plan: entitlement.planID});
  return code;
}

async function processWebhook(event, env) {
  if (!SUPPORTED_EVENTS.has(event.type)) return {ignored: true};
  const duplicate = await env.LICENSE_STATE.get(`event:${event.id}`);
  if (duplicate) return {duplicate: true};
  const provider = new StripeManagedPaymentsProvider(env);
  const details = await provider.entitlement(event);
  if (!details.email && details.subscriptionID) {
    details.email = normalizeEmail(await env.LICENSE_STATE.get(`subscription:${details.subscriptionID}`));
  }
  if (!details.email || !details.planID || !details.periodEnd) throw new Error('Webhook lacks entitlement fields');
  const entitlement = {
    email: details.email,
    planID: details.planID,
    tier: details.tier,
    seatCount: details.seatCount,
    subscriptionID: details.subscriptionID,
    paidThrough: details.periodEnd,
    expires: details.periodEnd + GRACE_SECONDS,
    active: event.type === 'invoice.paid' || event.type === 'checkout.session.completed' ||
      (event.type !== 'customer.subscription.deleted' && ACTIVE_STATUSES.has(details.status))
  };
  await env.LICENSE_STATE.put(`entitlement:${details.email}`, JSON.stringify(entitlement));
  if (details.subscriptionID) await env.LICENSE_STATE.put(`subscription:${details.subscriptionID}`, details.email);
  await env.LICENSE_STATE.put(`event:${event.id}`, '1', {expirationTtl: 90 * 24 * 60 * 60});
  if (event.type === 'checkout.session.completed' || event.type === 'invoice.paid') await issueCode(details.email, entitlement, env);
  return {processed: true};
}

async function signLicense(entitlement, env) {
  if (!env.LICENSE_PRIVATE_KEY_PKCS8_BASE64) throw new Error('Signing key unavailable');
  const key = await crypto.subtle.importKey('pkcs8', fromBase64(env.LICENSE_PRIVATE_KEY_PKCS8_BASE64), {name: 'Ed25519'}, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    email: entitlement.email,
    expiresAt: iso(entitlement.expires),
    issuedAt: iso(now),
    // Foundation's UUID encoder emits uppercase hex. Sign those exact bytes so
    // the app can reproduce the canonical payload during offline verification.
    licenseID: crypto.randomUUID().toUpperCase(),
    paidThrough: iso(entitlement.paidThrough),
    planID: entitlement.planID,
    seatCount: entitlement.seatCount,
    tier: entitlement.tier
  };
  const signature = await crypto.subtle.sign('Ed25519', key, encoder.encode(canonical(payload)));
  return {payload, signature: btoa(String.fromCharCode(...new Uint8Array(signature)))};
}

async function readBody(request) {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new Error('JSON required');
  return request.json();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/webhooks/stripe') {
      const body = await request.text();
      if (!await verifyStripeSignature(body, request.headers.get('Stripe-Signature'), env.STRIPE_WEBHOOK_SECRET)) return json({error: 'invalid signature'}, 400);
      try { return json(await processWebhook(JSON.parse(body), env)); }
      catch (_) { return json({error: 'webhook rejected'}, 422); }
    }
    if (request.method === 'POST' && url.pathname === '/activation/request') {
      try {
        const email = normalizeEmail((await readBody(request)).email);
        if (!email) return json({error: 'invalid request'}, 400);
        const raw = await env.LICENSE_STATE.get(`entitlement:${email}`);
        if (raw) {
          const entitlement = JSON.parse(raw);
          if (entitlement.expires >= Math.floor(Date.now() / 1000)) await issueCode(email, entitlement, env);
        }
        return new Response(null, {status: 204, headers: {'Cache-Control': 'no-store'}});
      } catch (_) { return json({error: 'invalid request'}, 400); }
    }
    if (request.method === 'POST' && url.pathname === '/activation/exchange') {
      try {
        const body = await readBody(request);
        const email = normalizeEmail(body.email);
        const rawCode = email && await env.LICENSE_STATE.get(`code:${email}`);
        const rawEntitlement = email && await env.LICENSE_STATE.get(`entitlement:${email}`);
        if (!email || !rawCode || !rawEntitlement) return json({error: 'invalid activation'}, 403);
        const code = JSON.parse(rawCode);
        const entitlement = JSON.parse(rawEntitlement);
        if (code.expires < Math.floor(Date.now() / 1000) || !constantTimeEqual(code.hash, await digest(String(body.code || '').trim())) || entitlement.expires < Math.floor(Date.now() / 1000)) return json({error: 'invalid activation'}, 403);
        await env.LICENSE_STATE.delete(`code:${email}`);
        return json(await signLicense(entitlement, env));
      } catch (_) { return json({error: 'activation unavailable'}, 503); }
    }
    const checkoutMatch = request.method === 'GET' && url.pathname.match(/^\/checkout\/([a-z-]+)$/);
    if (checkoutMatch) {
      const checkout = new StripeManagedPaymentsProvider(env).checkoutURL(checkoutMatch[1]);
      return checkout ? Response.redirect(checkout.toString(), 302) : json({error: 'checkout unavailable'}, 404);
    }
    if (request.method === 'GET' && url.pathname === '/subscription/manage') {
      const management = new StripeManagedPaymentsProvider(env).managementURL();
      return management ? Response.redirect(management.toString(), 302) : json({fallback: 'mailto:hello@screenplayos.com?subject=Cancel%20ScreenplayOS'});
    }
    return new Response('Not found', {status: 404});
  }
};
