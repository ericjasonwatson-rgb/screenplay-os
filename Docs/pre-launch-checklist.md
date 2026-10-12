# Pre-launch commerce checklist

Status: **not ready to charge**. Charging and enforcement remain off.

| Gate before any sale | Status | Evidence / remaining work |
|---|---|---|
| Generation lands in shot Takes | Done in source | Editable consent preview, provider adapter, content-addressed image storage, provenance |
| Multiple/imported Takes and reversible selection | Done in source | Edit uses selected board image; switching is undoable and retains media |
| Synced dialogue/music/effects audio lanes | Done in source | Imported local audio, timing model, playback sync, EDL/FCPXML references |
| Continuity bible in document and prompt injection disclosure | Done in source | Character/location/style data persists; prompt review shows injected entries |
| Provenance and project cost ledger/CSV | Done in source | Unknown cost remains unknown; provider-reported actual replaces estimate |
| Performer consent continues to fail closed | Done/tested | Existing consent ledger/generation tests remain in suite |
| Entitlements centralized, enforcement default off | Done in source | Free/Pro/Studio model; default grants Pro features; Studio collaboration remains gated/unbuilt |
| Core access can never be gated | Done/tested | Open/save/autosave/recovery/PDF/FDX/read-existing always allowed by type |
| Offline signed licenses and 14-day grace | Foundation done | Ed25519 verifier and file-entry UI; production key/public key replacement still required |
| License status UI acceptance | Not done | Manually test valid, grace, expired, invalid, VoiceOver, and recovery copy on signed build |
| Pricing | Partly done | One JSON config; Pro/founding/minimum-seat values encoded; owner must set Studio monthly/yearly prices |
| Merchant of record | Stripe sandbox selected | Managed Payments selected 2026-10-11; no live products, prices or webhook |
| Webhook/license service | Test foundation done | Stripe signature verification, four lifecycle events, idempotency, one-time activation and Ed25519 signing are locally tested; deployment, durable storage, email delivery, monitoring and threat review remain |
| Production signing key custody | Not done | Create outside Git in managed secrets/HSM; rotate and recover; replace placeholder public key |
| Terms, Privacy, EULA | Drafted only | Attorney review and owner decisions required; publish only approved final text |
| Refund/support policy | Not done | Owner and counsel decision; align merchant settings and customer copy |
| Privacy/security | Source review done; operations open | Keys absent from logs/exports; no telemetry; complete hosted-system retention/access/incident plan |
| Full automated suite | Must be green at review | Run only `Scripts/test.sh` |
| Manual app acceptance | Not done | Disposable projects only: generation, take switch, audio sync, continuity injection, ledger export, license states |
| Release/build/site | Explicitly excluded | No build, tag, push, publish, deployment, account or signing changes in this task |

## Security review findings

- AI secrets remain in Keychain and outside documents, logs, activity exports, and ledger CSV.
- Every outbound creative request retains explicit preview/consent. Automated tests use mock adapters and send no screenplay content.
- Asset provenance is local and project-bound. Content-addressed media rejects invalid or remote inputs.
- License files are Ed25519 signed; editing tier, seats, dates, plan, or version invalidates the signature. The private key is never shipped. This is an authorization boundary, not invasive DRM.
- Enforcement must not be enabled with the placeholder public key or before production acceptance. License expiry is non-hostile and cannot block core file access.
- No analytics or screenplay telemetry was added. The future webhook should store transaction/license metadata only, never screenplay content or AI keys.

## Owner decisions

1. Set Studio monthly and annual per-seat prices within or outside the proposed range.
2. Define founding eligibility continuity and perpetual-fallback edge cases with counsel.
3. Approve refund, support, device/seat, and privacy contact policies.
4. Choose hosting and secret custody for the license signer.

