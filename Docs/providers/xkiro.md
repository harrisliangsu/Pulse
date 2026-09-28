# xKiro

Profiled provider: [`Sources/Pulse/Providers/Profiled/XKiroUsageService.swift`](../../Sources/Pulse/Providers/Profiled/XKiroUsageService.swift). User setup: [../setup/xkiro.md](../setup/xkiro.md). Not AWS Kiro (`kiro`), which is a separate built-in provider.

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.xkiro.com/v1/usage`, bearer token. Documented as unmetered.
- **Reply:** `{ object: "usage", plan, user, windows: [{ kind, window_sec, spent_usd, cap_usd, remaining_usd, resets_in_sec }], free_tokens: { used_today, limit_per_day, remaining }, wallet: { balance_usd, held_usd } }`; money is fixed-point strings. `object` must be `"usage"`.
- **Windows:**
  - Each plan window → kind by its stated `window_sec` (18000 → `.fiveHour`, 604800 → `.weekly`, otherwise `.other`), used = `spent_usd` / `cap_usd`, reset now + `resets_in_sec`. A length that isn't whole hours, or a cap of 0, is left off.
  - Free tokens → `.daily`, used = `used_today` / `limit_per_day`, reset at the next 00:00 UTC — xKiro's documented rule, not a reply field. `limit_per_day: null` (unlimited) draws nothing.
- **Balance:** `wallet.balance_usd` → `creditBalance` (currency-formatted) and `creditRemaining` in USD; `reportsSpendableBalance` is on.
- **Plan:** `plan`, capitalized; `null` (pay as you go) shows none.
- **Beyond CodexBar:** CodexBar reads only the free tokens. The plan windows and wallet are read from the shape in xKiro's own docs (docs.xkiro.com/api/usage), which CodexBar's docs cite.
- **Left out:** `held_usd` (funds reserved for requests in flight), `user`.
- **Evidence:** second-hand. The shape comes from CodexBar's xKiro plugin and tests (MIT) and the example replies in xKiro's docs; no live account has been read. The fixture is `Tests/PulseTests/Fixtures/xkiro-usage.json`.
