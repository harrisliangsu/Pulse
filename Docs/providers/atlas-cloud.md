# Atlas Cloud

Profiled provider: [`Sources/Pulse/Providers/Profiled/AtlasCloudUsageService.swift`](../../Sources/Pulse/Providers/Profiled/AtlasCloudUsageService.swift). User setup: [../setup/atlas-cloud.md](../setup/atlas-cloud.md).

- **Credential:** an API key the user pastes, with account-balance read permission. Nothing is read from this Mac.
- **Route:** `GET https://api.atlascloud.ai/public/v1/balance`, bearer token.
- **Reply:** `{ object: "balance", scope: "account", available: { value: "<decimal string>", currency: "usd" } }`. `object` and `scope` must match; `value` must be a decimal string; `currency` a three-letter code.
- **Windows:** none. `creditBalance` is the value formatted in the stated currency; `creditRemaining` carries it with the upper-cased ISO code; `reportsSpendableBalance` is on. A negative balance is kept (money owed).
- **Differs from CodexBar:** CodexBar accepts only `usd`; Pulse accepts any three-letter code and formats in it.
- **Left out:** Coding Plan quotas (another meter, another route).
- **Evidence:** second-hand. The shape comes from CodexBar's Atlas Cloud plugin and docs (MIT), which cite Atlas Cloud's billing API docs; no live account has been read. The fixture is `Tests/PulseTests/Fixtures/atlas-cloud-balance.json`.
