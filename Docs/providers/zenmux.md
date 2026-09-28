# ZenMux

Profiled provider: [`Sources/Pulse/Providers/Profiled/ZenMuxUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ZenMuxUsageService.swift). User setup: [../setup/zenmux.md](../setup/zenmux.md).

- **Credential:** a Management API key the user pastes. Inference keys are refused (401/403 → "That key was refused").
- **Route:** `GET https://zenmux.ai/api/v1/management/subscription/detail`, then `GET …/payg/balance`, both bearer.
- **Reply:** `{ success: true, data: { plan: { tier }, quota_5_hour: { usage_percentage, resets_at, … }, quota_7_day: { … }, quota_monthly: { max_flows } } }`. `usage_percentage` is a fraction (0.0715 = 7.15%). Balance: `{ success: true, data: { currency, total_credits } }`.
- **Windows:** `quota_5_hour` → `.fiveHour`, `quota_7_day` → `.weekly`, both named for their length. The fraction as reported; not clamped, so over 1 reads as spent. A missing or negative figure drops that quota.
- **Balance:** `total_credits` in the named currency (`reportsSpendableBalance`), kept negative when overdue. Best-effort: a failed or unreadable balance leaves the quotas standing. CodexBar fails the whole refresh when the balance request is refused; Pulse does not, since the quotas were just read with the same key.
- **Plan:** `plan.tier`, capitalized.
- **Left out:** `quota_monthly`, which states a size and no amount used; the flow counts and USD values, which only restate the fraction.
- **Evidence:** second-hand. The shapes come from CodexBar's ZenMux plugin and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/zenmux-*.json`.
