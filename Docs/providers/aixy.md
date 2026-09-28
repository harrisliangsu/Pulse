# Aixy

Profiled provider: [`Sources/Pulse/Providers/Profiled/AixyUsageService.swift`](../../Sources/Pulse/Providers/Profiled/AixyUsageService.swift). User setup: [../setup/aixy.md](../setup/aixy.md).

- **Credential:** an API key the user pastes. Hosted gateway only.
- **Route:** `GET https://api.aixy-gateway.com/v1/usage`, bearer token.
- **Reply:** `{ object: "key.usage", currency: "USD", key: { id, project_id }, budgets: [{ id, interval, enforcement, limit_usd, applies_to: [{ api_key_id, project_id }], availability: { status, spent_usd, reserved_usd }, spend_status, spend_usd, resets_at }] }`. `object` and `currency` must be those values. Amounts may be numbers or decimal strings.
- **Windows:** one per budget whose balance is known — a hard budget when `availability.status` is `available` (used = `spent_usd + reserved_usd`, what the gateway enforces), a monitor budget when `spend_status` is `available` (used = `spend_usd`) — over `limit_usd > 0`. `daily` → `.daily`, `weekly` → `.weekly` (stated lengths), `monthly` → `.monthly` (30 days as a sort key), `lifetime` → `.spend` with no reset. One budget per period: hard before monitor, then the one nearest its limit. A budget whose `applies_to` names another key or project is skipped.
- **Left out:** budgets whose balance is unavailable (a limit with no figure); the budget's scope (key/team/project…), which is not a model name; the last seven days' attributed spend, which Aixy says may be estimated and has no limit. A self-hosted or dedicated gateway's base URL: a profiled provider has either a fixed host or a required address (`keyAndAddress`), not an optional one.
- **Evidence:** second-hand. The shape comes from the contract CodexBar's Aixy plugin (MIT) validates; CodexBar ships no Aixy reply of its own and no live account has been read. Fixture: `Tests/PulseTests/Fixtures/aixy-usage.json`.
