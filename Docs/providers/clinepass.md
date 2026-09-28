# ClinePass

Profiled provider: [`Sources/Pulse/Providers/Profiled/ClinePassUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ClinePassUsageService.swift). User setup: [../setup/clinepass.md](../setup/clinepass.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.cline.bot/api/v1/users/me/plan/usage-limits`, bearer token.
- **Reply:** `{ success, data: { limits: [{ type, percentUsed, resetsAt }] } }`. `success` must be `true`.
- **Windows:** `five_hour` (5 h), `weekly` (7 d), `monthly` — a billing month, so its 30 days are a sort key only (`reportsLength: false`). Any other `type` is left off: nothing states its length or its name.
- **Figures:** `percentUsed` as reported. A negative or missing figure drops that limit; none left is "No limits reported".
- **Evidence:** second-hand. The shape comes from CodexBar's ClinePass plugin and its tests (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/clinepass-usage-limits.json`.
