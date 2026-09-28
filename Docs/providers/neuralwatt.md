# Neuralwatt

Profiled provider: [`Sources/Pulse/Providers/Profiled/NeuralwattUsageService.swift`](../../Sources/Pulse/Providers/Profiled/NeuralwattUsageService.swift). User setup: [../setup/neuralwatt.md](../setup/neuralwatt.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.neuralwatt.com/v1/quota`, bearer token.
- **Reply:** `{ balance: { credits_remaining_usd, total_credits_usd, credits_used_usd }, subscription: { plan, billing_interval, current_period_start, current_period_end, kwh_included, kwh_used, kwh_remaining } | null, key: { allowance: { limit_usd, spent_usd, period } } }`. `balance` must be there.
- **Windows:** the subscription first — `kwh_used / kwh_included`, or `kwh_used / (kwh_used + kwh_remaining)` when the size is not stated (both figures the service's). `billing_interval: month` → `.monthly`; otherwise `.other(seconds:)` from the period, or `.credits` without one. The period's length is claimed only when both ends are reported; its end is the reset. Then the key allowance, `.spend`: `spent_usd / limit_usd`; `daily`/`weekly` periods are stated lengths, anything else a 30-day sort key.
- **Balance:** `credits_remaining_usd`, or `total − used` when only those two are reported, as USD (`reportsSpendableBalance`). Kept apart from the subscription: prepaid credit does not reset.
- **Left out:** `allowance.blocked` drawn as 100% (a flag, not a figure); the current month's `cost_usd` (spend with no limit); a missing figure is never read as zero.
- **Evidence:** second-hand. The shape comes from CodexBar's Neuralwatt plugin and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/neuralwatt-quota.json`.
