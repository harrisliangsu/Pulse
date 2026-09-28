# Mistral

Profiled provider: [`Sources/Pulse/Providers/Profiled/MistralUsageService.swift`](../../Sources/Pulse/Providers/Profiled/MistralUsageService.swift). User setup: [../setup/mistral.md](../setup/mistral.md).

- **Credential:** `sessionCookie(host: "mistral.ai", cookies: ["ory_session_*", "csrftoken"])`. Mistral signs in with Ory, whose session cookie is `ory_session_<deployment suffix>` (on `Domain=mistral.ai`); the suffix is not published. `ProviderProfile.keep` treats a trailing `*` as a prefix, so Read from browser finds it; pasting the `Cookie:` header also works. The fetch itself keeps only `ory_session_*` and `csrftoken` from whatever is stored; no `ory_session_*` → "Read a browser session".
- **Route:** three GETs, cookies set by hand (`httpShouldHandleCookies = false`), redirects **not** followed, 15 s timeout.
  1. `https://admin.mistral.ai/api/billing/credits` — required. A 3xx (Mistral's answer to a dead session is a redirect to `auth.mistral.ai`), 401 or 403 → "The browser session expired"; the rest through `ProfileHTTP.classify`.
  2. `https://admin.mistral.ai/subscription` — best-effort. A Next.js page: the `self.__next_f.push([1, "…"])` strings are joined into one stream, and the `api_budget` / `vibe_budget` objects in it are read. Two different objects under one name → neither.
  3. `https://console.mistral.ai/api-ui/trpc/billing.vibeUsage?batch=1&input={"0":{"json":null,"meta":{"values":["undefined"],"v":1}}}` — only when step 2 has no Vibe allowance and a `csrftoken` is held; sends the same token as `X-CSRFToken`.
- **Replies:**
  - credits: `{ wallet_amount, credit_notes_amount, ongoing_usage_balance, currency }`.
  - budget: `{ usage_percentage, initial_budget, currency, reset_at }`; `reset_at` may be React's `$D<ISO date>`.
  - Vibe: `[{ result: { data: { json: { usage_percentage, reset_at, … } } } }]`.
- **Windows:** `mistral.api` (scope "API") and `mistral.vibe` (scope "Vibe"), `.monthly`, `usedFraction = usage_percentage / 100`. A subscription month is a billing month, so 30 days is a sort key only (`reportsLength: false`). A negative or missing percentage is left off. `initial_budget` is not used: the percentage is Mistral's own.
- **Balance:** `wallet_amount + credit_notes_amount − ongoing_usage_balance` in `currency` — arithmetic on three figures Mistral reports, not an estimate. Missing wallet or currency, or a result below zero (a debt, not a balance), is left off. `reportsSpendableBalance: true`.
- **Nothing at all** (no allowance, no balance) → "No limits reported".
- **Left out:** CodexBar's headline month spend and token totals from `GET /api/billing/v2/usage`, which it prices with its own table — an estimate, and Pulse shows only what Mistral reports. Spend-only figures have no place in Pulse yet either.
- **Evidence:** second-hand. The shapes come from CodexBar's Mistral provider, `docs/mistral.md` and its tests (MIT); no live account has been read. The redirect-on-expiry behaviour and the cookie domain were seen from outside (an unauthenticated request to `auth.mistral.ai`), not with a session. Fixtures: `Tests/PulseTests/Fixtures/mistral-*.json`; the subscription page is built in `MistralTests`.
