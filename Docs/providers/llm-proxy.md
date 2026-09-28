# LLM API Key Proxy

Profiled provider: [`Sources/Pulse/Providers/Profiled/LLMProxyUsageService.swift`](../../Sources/Pulse/Providers/Profiled/LLMProxyUsageService.swift). User setup: [../setup/llm-proxy.md](../setup/llm-proxy.md).

- **Credential:** `.keyAndAddress` — the proxy's key and address (`GatewayAddress` rules). Readings carry a `sourceScope` of address + key fingerprint; `requiresScopeMatch` is on.
- **Route:** `GET <address>/v1/quota-stats` (the root or a `/v1` base both lead here), bearer token.
- **Reply:** `{ providers: { <upstream>: { credential_count, active_count, exhausted_count, total_requests, tokens { input_cached, input_uncached, output }, approx_cost, quota_groups } }, summary { total_requests, total_tokens, approx_cost } }`. `quota_groups` is keyed by group name or a plain list of `{ remaining_percent, reset_time }`; a malformed one is skipped without failing the reply.
- **Windows:** one per quota group with `remaining_percent` in 0–100: `.credits`, used = 100 − remaining, reset `reset_time`, scope `<upstream> · <group>` (the group name is dropped when it is `default` or the list has no names). No group states its period, so 1 day is a sort key only (`reportsLength: false`).
- **Differs from CodexBar:** CodexBar folds every group into one figure — the lowest remainder anywhere — which no upstream reported. Pulse keeps each group.
- **Left out:** request, token and approximate-cost totals (spend with no limit — Pulse has nowhere to show them yet), active/total key counts.
- **Evidence:** second-hand. The shape comes from CodexBar's LLM Proxy plugin, docs and tests (MIT); no live proxy has been read. The fixture is `Tests/PulseTests/Fixtures/llm-proxy-quota-stats.json`.
