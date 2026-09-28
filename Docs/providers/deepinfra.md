# DeepInfra

Profiled provider: [`Sources/Pulse/Providers/Profiled/DeepInfraUsageService.swift`](../../Sources/Pulse/Providers/Profiled/DeepInfraUsageService.swift). User setup: [../setup/deepinfra.md](../setup/deepinfra.md).

- **Credential:** an API key the user pastes.
- **Route:** `GET https://api.deepinfra.com/payment/checklist?compute_owed=true`, bearer token.
- **Reply:** `{ stripe_balance, recent, limit?, suspended?, suspend_reason? }`, US dollars. `stripe_balance` and `recent` must be numbers.
- **Balance:** DeepInfra's ledger is inverted — prepaid money is a negative `stripe_balance`. Money left = `−(stripe_balance + max(recent, 0))`, as CodexBar computes it from the same two figures; a positive ledger (money owed) is a negative balance. USD, `reportsSpendableBalance`.
- **Windows:** only when `limit > 0`: `.spend`, `max(recent, 0) / limit`, a billing cycle whose length is not stated (30-day sort key, no reset).
- **Left out:** CodexBar's "balance health indicator" — 100% when suspended or out of money, 0% otherwise — which is a flag, not a share of anything. The `/payment/usage` month's cost (spend with no limit), so that request is not made at all.
- **Evidence:** second-hand. The shape comes from CodexBar's DeepInfra plugin and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/deepinfra-checklist.json`.
