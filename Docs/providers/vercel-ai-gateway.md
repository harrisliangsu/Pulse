# Vercel AI Gateway

Profiled provider: [`Sources/Pulse/Providers/Profiled/VercelAIGatewayUsageService.swift`](../../Sources/Pulse/Providers/Profiled/VercelAIGatewayUsageService.swift). User setup: [../setup/vercel-ai-gateway.md](../setup/vercel-ai-gateway.md).

- **Credential:** an AI Gateway API key the user pastes.
- **Route:** `GET https://ai-gateway.vercel.sh/v1/credits`, bearer token.
- **Reply:** `{ balance, total_used }`, both decimal strings in US dollars (the currency is Vercel's documented one; the reply does not name it). A `balance` that is not a decimal string is unreadable.
- **Windows:** none — the endpoint states no limit and no period. A balance-only reading.
- **Balance:** `balance` as USD, zero and negative kept (`reportsSpendableBalance`).
- **Left out:** `total_used`, lifetime spend with no limit beside it.
- **Evidence:** second-hand. The shape comes from CodexBar's Vercel plugin (MIT) and the Vercel REST reference it cites; no live account has been read. Fixture: `Tests/PulseTests/Fixtures/vercel-ai-gateway-credits.json`.
