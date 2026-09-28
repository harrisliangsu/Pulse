# Bifrost

Profiled provider: [`Sources/Pulse/Providers/Profiled/BifrostUsageService.swift`](../../Sources/Pulse/Providers/Profiled/BifrostUsageService.swift). User setup: [../setup/bifrost.md](../setup/bifrost.md).

- **Credential:** `.keyAndAddress` — a Bifrost virtual key and the gateway address (`GatewayAddress` rules: https, or http only on a private network). Readings carry a `sourceScope` of address + key fingerprint, and `requiresScopeMatch` is on.
- **Route:** `GET <address>/api/governance/virtual-keys/quota` (a trailing `/v1` on the typed address is dropped), key in `x-bf-vk`.
- **Reply:** `{ virtual_key_name, is_active, budgets: [...], rate_limits: [...], provider_configs: [{ provider, budgets }], model_configs: [{ provider, model_name, budgets }] }`; a budget is `{ id, max_limit, current_usage, reset_duration, last_reset, override_amount, override_mode, override_cycles_remaining, source_name }`.
- **Windows:** one per budget with a positive effective limit. Used = `current_usage` / (`max_limit` + `override_amount` while the override is in force: `forever`, or `cycles` with cycles remaining). Scope: none for the key's own budgets, the provider name for `provider_configs`, the model name for `model_configs`.
  - `reset_duration` names the kind: a Go duration (`1h`, `5h`, `24h`) → `.other` / `.fiveHour` / `.daily` with a stated length; `1d` → `.daily`, `1w`/`7d` → `.weekly`, `Nd`/`Nw` → `.other`; `1M` → `.monthly` (sort key, `reportsLength: false`); several months, `Q`, `Y`, a sub-hour duration or anything unparsed → `.spend` with no length claimed.
  - Reset: only for a Go-duration period, `last_reset + duration`, and only if that is still ahead. Day-and-longer periods may be calendar-aligned and the reply doesn't say, so none is drawn (as CodexBar).
- **Inactive key** with no budgets → "That key was refused".
- **Left out:** rate limits (token and request limits over the same period would both be named "N-hour limit" — Pulse has no unit label to tell them apart); per-model spend breakdown (spend with no limit). CodexBar's floor-loop that projects resets forward from an old `last_reset` is not done.
- **Evidence:** second-hand. The shape comes from CodexBar's Bifrost plugin (MIT); no live gateway has been read. The fixture is `Tests/PulseTests/Fixtures/bifrost-quota.json`.
