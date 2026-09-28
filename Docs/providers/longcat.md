# LongCat

Profiled provider: [`Sources/Pulse/Providers/Profiled/LongCatUsageService.swift`](../../Sources/Pulse/Providers/Profiled/LongCatUsageService.swift). User setup: [../setup/longcat.md](../setup/longcat.md).

- **Credential:** `.sessionCookie(host: "longcat.chat")`, keeping `passport_token` (required) and `uid` — the only names CodexBar's tests show. Requests go through an ephemeral session with no cookie jar and no redirects; a 3xx, 401 or 403 is an expired session.
- **Routes** (all on `https://longcat.chat`, with `Origin` and `Referer: /platform/usage`):
  1. `GET /api/v1/user-current` — required; proves the session. Its body (which carries a phone number and a session token) is only checked, never kept.
  2. `POST /api/pay/quota/metering/token-packs/summary` with `{}` — best-effort (some sessions are refused here).
  3. `GET /api/lc-platform/v1/tokenUsage` — only when the summary has no active pack; required then.
  4. `GET /api/lc-platform/v1/pending-fuel-packages` — best-effort.
- **Envelope:** `{ code, message, data }`. `code` 0 or 200 → `data` (must be an object); 401/403 → session expired; any other number → "The service returned an error."; a `code` that is not a number, or no JSON → "Couldn't read the reply."
- **Windows:**
  - `data.currentLot` with `status: ACTIVE` and `totalToken > 0`: `consumedToken ÷ totalToken` → `.credits` ("Credit allowance"), no reset, no length (30 days sort key).
  - otherwise `tokenUsage.data.usage` (`extData` is per model and not read): `usedToken ÷ totalToken`, or `(totalToken − availableToken) ÷ totalToken` when only the remainder is given → `.credits`. A reply with no `totalToken` is unreadable.
  - fuel packs: `(totalQuota − Σ list[].availableToken) ÷ totalQuota` → `.topUp` ("Top-up pack"), no reset (60 days sort key). `nextExpiry` is the soonest `expireTime` (epoch s/ms, ISO 8601, or `yyyy-MM-dd HH:mm:ss`) with its `availableToken`, via `UsageWindow.Expiry.soonest`.
- **Left out on purpose:** CodexBar fills a missing `consumedToken` with 0 and a fuel list with no `availableToken` with the whole total; both draw a ring nobody reported, so here that row is dropped. The account name from `user-current` is not shown (it is not a plan). `consumedRatio` is not used: the counts are.
- **Refresh pacing:** `spendingIsWatchedLocally` is left at its default (true). The allowance is spent on LongCat's servers with no clock to turn over, so by the rule it belongs with the unwatched providers — but `RefreshPacingTests` names that set, and adding LongCat to it is a shared change not made here.
- **Evidence:** second-hand. The shape comes from CodexBar's LongCat provider and its tests (MIT), whose field names it says were pinned against captured live replies; no live account has been read here. Fixtures: `Tests/PulseTests/Fixtures/longcat-*.json`.
