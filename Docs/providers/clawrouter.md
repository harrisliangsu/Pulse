# ClawRouter

Profiled provider: [`Sources/Pulse/Providers/Profiled/ClawRouterUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ClawRouterUsageService.swift). User setup: [../setup/clawrouter.md](../setup/clawrouter.md).

- **Credential:** an API key the user pastes. Hosted service only.
- **Route:** `GET https://clawrouter.openclaw.ai/v1/usage`, bearer token.
- **Reply:** `{ budget: { configured, ledger, windowKey, limitMicros, spentMicros, remainingMicros }, usage: { summary, providers[] } }`. Money in micro-dollars, integers. `budget.configured` must be a boolean.
- **Windows:** one, `.monthly`: `spentMicros / limitMicros`, both as reported, 30 days as a sort key. `configured: false`, or no positive limit, is "No limits reported".
- **Left out:** a reset. `windowKey` names the month (`…/2026-07`) but not when, or in which zone, it turns over; CodexBar assumes the 1st at 00:00 UTC, Pulse does not. The per-provider breakdown, request and token counts and `actualCostMicros` are spend with no limit. A base-URL override for another deployment: a profiled provider has either a fixed host or a required address, not an optional one.
- **Icon:** `openclaw`, ClawRouter's parent project's mark, already in Resources.
- **Evidence:** second-hand. The shape comes from CodexBar's ClawRouter plugin and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/clawrouter-*.json`.
