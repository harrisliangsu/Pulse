# Moonshot

Profiled provider: [`Sources/Pulse/Providers/Profiled/MoonshotUsageService.swift`](../../Sources/Pulse/Providers/Profiled/MoonshotUsageService.swift). User setup: [../setup/moonshot.md](../setup/moonshot.md).

The Kimi Open Platform API balance — not Kimi Code, which is its own (hand-written) provider.

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET /v1/users/me/balance`, bearer token, on one of two hosts:
  - international `https://api.moonshot.ai` — USD;
  - China mainland `https://api.moonshot.cn` — CNY.
- **Region is found, not chosen.** Profiled providers have no region picker (CodexBar has one, and binds each saved key to it). Pulse asks the international host; a 401/403 there is retried once on the China host — both are Moonshot's own. The host that accepted a key is kept in memory for the launch and asked first next time. Refused by both → `.apiKeyRefused`. Any other failure (429, 5xx, no answer) stops at the host that gave it: it says nothing about the key.
- **Reply:** `{ code, scode, status, data: { available_balance, voucher_balance, cash_balance } }`. `code` must be an integer and `status` a boolean, or the reply is unreadable; `code ≠ 0` or `status: false` → `.serverError`. `available_balance` must be a number.
- **Windows:** none. The platform reports no allowance.
- **Balance:** `available_balance`, in the currency of the host that answered (the reply names none), including a negative figure — a deficit is shown as one. `creditRemaining`, `reportsSpendableBalance`.
- **Left out:** `voucher_balance` and `cash_balance` separately (CodexBar adds a deficit note when cash is negative; the available figure already carries it); `MOONSHOT_API_KEY` / `MOONSHOT_REGION` environment variables.
- **Missing shared piece:** a region setting for profiled providers. With one, the key would go only to the chosen host, as in CodexBar, and `requiresScopeMatch` would become true.
- **Icon:** Lobe Icons `moonshot` (the MoonshotAI mark, monochrome) — not `kimi`, which is Kimi Code's.
- **Evidence:** second-hand. The shape comes from CodexBar's Moonshot plugin (`moonshot.ts`), `MoonshotRegion` and their tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/moonshot-balance.json`; the two-host exchange in the tests is a stub.
