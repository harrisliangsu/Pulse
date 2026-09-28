# Codebuff

Profiled provider: [`Sources/Pulse/Providers/Profiled/CodebuffUsageService.swift`](../../Sources/Pulse/Providers/Profiled/CodebuffUsageService.swift). User setup: [../setup/codebuff.md](../setup/codebuff.md).

- **Credential:** `apiKey(optional: true)`. The pasted key first (401/403 → `.apiKeyRefused`); otherwise the `codebuff` CLI's session token from `~/.config/manicode/credentials.json` — `default.authToken`, then a top-level `authToken` (401/403 → `.localLoginExpired`). Neither → `.apiKeyMissing`. The file is only read.
- **Routes** (bearer token, both on `www.codebuff.com`):
  - `POST /api/v1/usage`, `Content-Type: application/json`, body `{"fingerprintId":"pulse-usage"}` — the CLI's own call; it reads, and changes nothing CodexBar documents. Required.
  - `GET /api/user/subscription` — only with the CLI's token, as CodexBar does (an API key reads credits only). Asked alongside the first; any failure is ignored and the credits stand.
- **Reply (usage):** `{ usage | used, quota | limit, remainingBalance | remaining, next_quota_reset, autoTopupEnabled }`. Figures are numbers or numeric strings; a negative or non-numeric one is dropped. `next_quota_reset` is ISO 8601 or seconds/milliseconds since 1970. Not a JSON object → unreadable.
- **Reply (subscription):** `{ subscription: { displayName, tier, status, billingPeriodEnd }, displayName, tier, rateLimit: { weeklyUsed | used, weeklyLimit | limit, weeklyResetsAt }, email }`.
- **Windows:**
  - `.credits`: `usage / quota`, only when both are reported and `quota > 0`; resets at `next_quota_reset`. No period is stated, so 30 days is a sort key only.
  - `.weekly`: `weeklyUsed / weeklyLimit`, only when both are reported and the limit is above zero; the name states the week (`reportsLength: true`); resets at `weeklyResetsAt`.
  - Sorted shortest first. Nothing at all (no window, no balance) → "No limits reported".
- **Balance:** `remainingBalance` as a plain number (credits, not money — no `creditRemaining`, no `reportsSpendableBalance`), the way Codex's credit balance is shown.
- **Plan:** the subscription's `displayName`, else `tier`, first letter capitalised.
- **Left out:** CodexBar's 100% credit bar when the quota is missing or zero — Pulse draws nothing; CodexBar's weekly bar with a missing `weeklyUsed` read as 0 — Pulse needs both figures; `autoTopupEnabled`, `billingPeriodEnd`, `status`, `email`; the `CODEBUFF_API_KEY` / `CODEBUFF_API_URL` environment variables.
- **Icon:** none in Lobe Icons; the generic `extension` mark.
- **Evidence:** second-hand. The shapes come from CodexBar's Codebuff provider (`CodebuffUsageFetcher`, `CodebuffSettingsReader`, `CodebuffUsageSnapshot`) and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/codebuff-usage.json`, `codebuff-subscription.json`.
