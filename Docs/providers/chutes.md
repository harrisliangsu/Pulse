# Chutes

Profiled provider: [`Sources/Pulse/Providers/Profiled/ChutesUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ChutesUsageService.swift). User setup: [../setup/chutes.md](../setup/chutes.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.chutes.ai/users/me/subscription_usage`, bearer token.
- **Reply (as CodexBar reads it):** optionally wrapped in `data`/`result`; `subscription { active, status, plan_name, current_period_end }`, a monthly payload (`monthly`, `monthly_usage`, `billing_period`) and a rolling payload (`rolling`, `rolling_window`, `rolling_4h`, `four_hour`, …), each with used/limit/remaining figures, a reset and sometimes `window_minutes`. Keys are compared lower-cased with punctuation dropped.
- **Windows:**
  - Rolling → `.other(seconds:)` (or `.fiveHour` / `.daily` when that is the length), **only when its length is stated**: `window_minutes`/`window_hours`/`window_seconds`, or a key that names four hours (`rolling_4h`, `four_hour`, `window_4h`). A bare `rolling`/`rolling_window` with no length is left off.
  - Monthly → `.monthly`, sort key 30 days, `reportsLength: false`.
  - Figures: `used` (or `usage`, `requests`, `tokens`, …) out of `limit` (or `cap`, `max`, `quota`, …); or `limit` − `remaining`; or a stated `percent_used` on a 0–100 scale. A limit of 0 draws nothing.
- **No plan:** an inactive subscription (`active: false`, or status `free`/`inactive`/`canceled`/`expired`/`none`) with nothing to show → "This account has no plan with usage limits".
- **Left out:** CodexBar's deep search of the whole reply for any object with limit-like numbers, its default of 240 minutes / 30 days where no length is given, its `|x| < 1 → ×100` percentage heuristic, and its fallback to `/users/me/quotas` + `/users/me/quota_usage/{chute_id}` (per-chute pay-as-you-go quotas with no stated period, one request per chute).
- **Evidence:** second-hand, and CodexBar's parser is itself tolerant of several guessed shapes. The fixture `Tests/PulseTests/Fixtures/chutes-subscription-usage.json` is CodexBar's test body; no live account has been read.
