# Approval request binding v1 — non-authorizing contract

This small cross-platform Swift target holds deterministic metadata for a future reviewer to inspect.
It does not authorize transfers, sign messages, issue request IDs, or transmit client assets.

## Bound fields
Project UUID, request UUID, registered agent and destination IDs, requested purpose,
SHA-256 of exact content to transfer and applicable policy, byte length, issue and expiry seconds.
Canonical bytes are length-prefixed UTF-8, tagged with a versioned domain label.

## Security limits
- Digests must be computed by a trusted gateway over actual assembled outbound bytes,
  not accepted from an agent. Destination ID must map to a registry maintained by
  the helper; never connect to a user-supplied URL using these fields.
- The gateway must allocate request IDs and preserve a used-ID registry; merely
  changing request ID can bypass request-scoped replay protection.
- Caller-supplied timestamps or agent identities cannot be trusted.
- Expiry checking and signed-approval verification must occur **at dispatch**.
- A future reviewer UI must display exact content/purpose/destination/risk and require
  fresh user presence. A signed object cannot replace this review.
- These pure unit tests demonstrate deterministic encoding only, not real security.

No code in this target is imported by the agent-facing XPC helper, and the helper
continues to deny all transfers in PR #10. Use synthetic data only.
