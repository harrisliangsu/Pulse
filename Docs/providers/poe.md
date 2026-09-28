# Poe

Profiled provider: [`Sources/Pulse/Providers/Profiled/PoeUsageService.swift`](../../Sources/Pulse/Providers/Profiled/PoeUsageService.swift). User setup: [../setup/poe.md](../setup/poe.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.poe.com/usage/current_balance`, bearer token.
- **Reply:** `{ current_point_balance }`, a number or a numeric string. Missing or non-numeric is "Couldn't read the reply".
- **Windows:** none. The balance goes in `creditBalance` via the shared `"%@ points"` string. Points are not money: no `creditRemaining`, `reportsSpendableBalance` off.
- **Left out:** `GET /usage/points_history` (paged, up to five requests) — points spent per day, per bot and per usage type over 30 days. That is spend with no limit behind it, which Pulse has nowhere to show yet, so the request is not made.
- **Evidence:** second-hand. The shape comes from CodexBar's Poe plugin and docs (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/poe-current-balance.json`.
