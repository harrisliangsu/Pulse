# xAI API

Profiled provider: [`Sources/Pulse/Providers/Profiled/XAIAPIUsageService.swift`](../../Sources/Pulse/Providers/Profiled/XAIAPIUsageService.swift). User setup: [../setup/xai-api.md](../setup/xai-api.md). Not Grok ([grok.md](grok.md)): that is the consumer subscription, and nothing is shared between the two.

- **Credential:** one field, `TeamID:ManagementKey`, split at the first colon, like Volcengine's key pair. The balance is per team and the key does not name one. A team id containing `/` or equal to `.`/`..` is refused before anything is sent; the id is otherwise percent-encoded into the path.
- **Route:** `GET https://management-api.x.ai/v1/billing/teams/{team}/prepaid/balance`, bearer token (a management key; inference keys are refused).
- **Reply:** `{ total: { val: "<cents>" } }` — an inverted ledger in string cents, so `"-1234"` is $12.34 left. Anything that isn't a cent amount is "Couldn't read the reply", never $0.00.
- **Shows:** `creditBalance` and `creditRemaining` in USD; no window. `reportsSpendableBalance`, so the low-balance line is offered.
- **Caveat:** the ledger is the **posted** balance, updated when a billing cycle closes, so mid-cycle it can read higher than the console's live remainder (CodexBar's docs, from a live account).
- **Left out:** the thirty-day spend history (`POST …/usage`) — spend with no limit, which Pulse has no place for.
- **Evidence:** second-hand, from CodexBar's xAI provider and docs (MIT). Fixture: `Tests/PulseTests/Fixtures/xai-api-prepaid-balance.json`.
