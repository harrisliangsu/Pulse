# Augment Code

Profiled provider: [`Sources/Pulse/Providers/Profiled/AugmentUsageService.swift`](../../Sources/Pulse/Providers/Profiled/AugmentUsageService.swift). User setup: [../setup/augment.md](../setup/augment.md).

- **Credential:** a browser session, `.sessionCookie(host: "app.augmentcode.com", cookies: ["_session", "web_rpc_proxy_session"])`. `_session` is required. A 401 or 403 is `.sessionExpired`. `~/.augment` (the `auggie` CLI's folder) is only a presence hint for the chooser.
- **Route:** `GET https://app.augmentcode.com/api/credits` (required) and `GET https://app.augmentcode.com/api/subscription` (optional — a failure there leaves the reading standing with no plan and no reset, as in CodexBar). Headers: `Cookie`, `Accept: application/json`.
- **Reply (credits):** `{ usageUnitsRemaining, usageUnitsConsumedThisBillingCycle, usageUnitsAvailable, usageBalanceStatus }`. A body that isn't a JSON object — a sign-in page served with a 200 — is unreadable.
- **Reply (subscription):** `{ planName, billingPeriodEnd (ISO 8601), email, organization }`.
- **Window:** one, `.credits` — the provider's own credits, with the reset it states and no length it claims (30 days is a sort key; `reportsLength: false`). `usedFraction = usageUnitsConsumedThisBillingCycle / usageUnitsAvailable`, both as reported; `isExhausted` when consumed reaches available. Reset: `billingPeriodEnd`.
- **Plan:** `planName`.

## Left out, deliberately

- **An inferred allowance.** When `usageUnitsAvailable` is missing or zero, CodexBar uses `remaining + consumed` as the limit. That is a denominator Augment did not state, so here there is no ring and the reading is "No limits reported".
- **The remaining count as a balance.** It is a count of credits, not money, and the ring already carries the same fact.
- **`usageBalanceStatus`** — its values aren't documented anywhere this could check, so it doesn't set `isExhausted`.
- **The `auggie account status` CLI route** CodexBar prefers. It parses human-formatted text that has already changed shape once; the browser session is the simpler route and needs nothing run.
- **Session keepalive.** CodexBar pings `/api/auth/session` on a timer and re-imports cookies before they expire. Pulse sends nothing on its own schedule but the reading, and says the session expired when it has.

## Unverified

- Which cookie carries the session. CodexBar accepts any of eleven names; `_session` is the one its tests show scoped to `app.augmentcode.com`, and `web_rpc_proxy_session` is kept beside it. If Augment's session lives in another cookie, **Read** will report no session found.
- That `usageUnitsAvailable` is the cycle's whole allowance rather than what is left. CodexBar reads it as the allowance, and so does this; its own test fixture (15 remaining, 10 consumed, 100 available) doesn't settle it.

## Evidence

Second-hand. The shapes come from CodexBar's Augment provider, its tests, and its notes on the CLI's output (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/augment-credits.json`, `augment-subscription.json`.
