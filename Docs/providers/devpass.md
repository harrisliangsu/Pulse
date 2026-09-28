# DevPass

Profiled provider: [`Sources/Pulse/Providers/Profiled/DevPassUsageService.swift`](../../Sources/Pulse/Providers/Profiled/DevPassUsageService.swift). User setup: [../setup/devpass.md](../setup/devpass.md).

- **Credential:** a regular LLM Gateway API key the user pastes.
- **Route:** `GET https://api.llmgateway.io/v1/key`, bearer token.
- **Reply:** `{ data: { devPlan: none|lite|pro|max, usage, limit, devPlanCreditsUsed, devPlanCreditsLimit, devPlanPremiumCreditsUsed, devPlanPremiumWeeklyLimit, devPlanPremiumWeekResetsAt } }`. Amounts are decimal strings. An unknown `devPlan` is unreadable.
- **Windows:** premium week → `.weekly` (seven days from the first premium request — stated), reset as reported; cycle credits → `.credits`, no reset (none is reported; none inferred), 30-day sort key; key limit → `.spend`, `usage / limit`, all-time, no reset. Each only when both figures are readable, non-negative, and the limit is above zero.
- **Plan:** `devPlan` capitalized, except `none`. Pay as you go with no key limit is "This account has no plan with usage limits".
- **Left out:** `devPlanCreditsRemaining`, which restates the cycle window.
- **Evidence:** second-hand. The shape comes from CodexBar's DevPass plugin and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/devpass-key.json`.
