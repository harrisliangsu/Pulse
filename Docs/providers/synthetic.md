# Synthetic

Profiled provider: [`Sources/Pulse/Providers/Profiled/SyntheticUsageService.swift`](../../Sources/Pulse/Providers/Profiled/SyntheticUsageService.swift). User setup: [../setup/synthetic.md](../setup/synthetic.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.synthetic.new/v2/quotas`, bearer token.
- **Reply:** named slots at the root or under `data`: `rollingFiveHourLimit { max, remaining, limited, nextTickAt, tickPercent }`, `weeklyTokenLimit { percentRemaining, maxCredits, remainingCredits, nextRegenAt, nextRegenCredits }`, `search.hourly { limit, requests, renewsAt }`, and `plan`.
- **Windows:**
  - `rollingFiveHourLimit` → `.fiveHour`, used = (`max` − `remaining`) / `max`. `limited: true` marks it spent.
  - `weeklyTokenLimit` → `.weekly`, used = 100 − `percentRemaining` (0–100 scale); failing that, from the `maxCredits` / `remainingCredits` dollar strings.
  - `search.hourly` → `.other(seconds: 3600)`, scope `Search` (Synthetic's search API, a product name), used = `requests` / `limit`, reset `renewsAt`.
- **No reset on the rolling lanes.** `nextTickAt` / `nextRegenAt` is the next regeneration slice, not a turnover; drawn as `resetsAt` it would move forward every few minutes and read as a reset each time.
- **Left out:** CodexBar's generic fallback (any object anywhere with a `limit`/`used` number, with a guessed length), its `value ≤ 1 → ×100` percentage heuristic, the regeneration figures (`tickPercent`, `nextRegenCredits`) and the weekly dollar figure as a separate cost row — Pulse has no place for a regeneration rate, and the percentage already carries the weekly allowance.
- **Evidence:** second-hand. The shape comes from CodexBar's Synthetic plugin, its docs and its parity/golden tests (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/synthetic-quotas.json`.
