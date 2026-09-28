# Venice

Profiled provider: [`Sources/Pulse/Providers/Profiled/VeniceUsageService.swift`](../../Sources/Pulse/Providers/Profiled/VeniceUsageService.swift). User setup: [../setup/venice.md](../setup/venice.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.venice.ai/api/v1/billing/balance`, bearer token.
- **Reply:** `{ canConsume, consumptionCurrency, balances: { usd, diem }, diemEpochAllocation }`. `canConsume` must be a boolean and `balances` an object, or the reply is unreadable; `consumptionCurrency` a string or null. Balances are numbers or numeric strings; null or `""` is missing; anything else is unreadable.
- **Windows:** none.
- **Balance:** the one the account spends from. `consumptionCurrency` `"DIEM"` with a DIEM balance → "90.50 DIEM" (the symbol is not translated; not money, so no `creditRemaining`). Otherwise the USD balance as money (`creditRemaining`, `reportsSpendableBalance`), else the DIEM balance. Neither → "No limits reported".
- **Left out, deliberately:**
  - `canConsume`. CodexBar draws it as 100% (false) or 0% (true, with a balance) — a health flag, not a percentage. Pulse invents no percentage, so it is only validated.
  - The DIEM epoch allocation ring (`(allocation − diem) / allocation`). Both figures are reported, but the reply states no epoch length or reset, and the balance already says what is left.
  - The web route: subscription credits from `https://outerface.venice.ai/api/user/session`, read with a browser session (its token's claims). A profiled provider has one credential kind, and the API key is the documented one.
- **Icon:** Lobe Icons `venice` (monochrome).
- **Evidence:** second-hand. The shape comes from CodexBar's Venice plugin (`venice.js`) and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/venice-balance.json`.
