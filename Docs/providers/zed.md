# Zed

Profiled provider: [`Sources/Pulse/Providers/Profiled/ZedUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ZedUsageService.swift). User setup: [../setup/zed.md](../setup/zed.md).

- **Credential:** `sessionCookie(host: "zed.dev", cookies: ["zed.session"])` — a zed.dev browser session, imported on request. **Not the editor's login:** Zed stores that in the Keychain (an internet password for `https://zed.dev`, account = user id), and reading it is a Keychain prompt with no existing Pulse mechanism behind it. CodexBar reads it directly (`GET https://cloud.zed.dev/client/users/me`, `Authorization: {user_id} {token}`); Pulse does not.
- **Route:** `GET https://cloud.zed.dev/frontend/billing/usage`, `Cookie` and `Accept: application/json`. The billing page's own frontend call; undocumented. 401/403 → `.sessionExpired`.
- **Reply:** `{ plan, current_usage: { edit_predictions: { used, limit }, token_spend: { spend_in_cents, limit_in_cents } } }`. `limit` is a number, `{ limited: n }`, `"unlimited"` or null. No `current_usage` object → unreadable.
- **Windows:**
  - `edit_predictions` → `.monthly`, scope "Edit Predictions", `used / limit`, only when both are reported and the limit is above zero. The reply names no period (Zed's plans count predictions by the month), so 30 days is a sort key only (`reportsLength: false`) and there is no reset time.
  - `token_spend` → `.spend`, `spend_in_cents / limit_in_cents`, only when a limit above zero is reported. Overspend is kept (above 100%) and marked exhausted. No reset time is reported.
  - A negative, boolean or missing figure drops that window. Nothing left is "No limits reported" — e.g. Pro with unlimited predictions and no spending limit.
- **Plan:** `plan`, `zed_pro_trial` → "Zed Pro Trial".
- **Left out:** spend with no limit (spend-only, and Pulse has nowhere to show it yet); CodexBar's "remaining budget" (limit − spend, a subtraction Pulse would be presenting as a reported balance); unlimited predictions, which CodexBar draws as 0% — Pulse draws nothing; the editor route's billing-cycle dates and overdue-invoice flag, which only that Keychain route returns.
- **Icon:** none in Lobe Icons; the generic `extension` mark.
- **Evidence:** second-hand. The shape comes from CodexBar's Zed plugin (`zed.js`) and its tests (MIT), which cite the endpoint evidence in CodexBar issue #3172; no live account has been read. Fixture: `Tests/PulseTests/Fixtures/zed-billing-usage.json`.
