# Abacus AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/AbacusUsageService.swift`](../../Sources/Pulse/Providers/Profiled/AbacusUsageService.swift). User setup: [../setup/abacus.md](../setup/abacus.md).

- **Credential:** a browser session read for host `abacus.ai` (covers `apps.abacus.ai`), kept to `sessionid`, `session_id`, `session_token`, `auth_token`, `access_token` — any one of them is enough (`|` alternatives in `ProviderProfile.keep`). The fetch applies the same filter again. **The names are unverified:** they are CodexBar's list of names "known to carry Abacus session state", but CodexBar accepts any of them (or any name containing `session`/`auth`/`sid`/`jwt`) and then sends the browser's whole jar. Pulse keeps only these five, so a session under any other name reads as "No session found".
- **Route:** both on `https://apps.abacus.ai`, sent concurrently, with `Cookie` and `Accept`. Redirects are refused; a 3xx, 401 or 403 is an expired session.
  - `GET /api/_getOrganizationComputePoints` — required.
  - `POST /api/_getBillingInfo`, body `{}` — optional. Its failure costs only the reset and the plan.
- **Reply:** both `{ success, result, error }`. `success: false` with an `error` mentioning expired/session/login/authenticate/unauthorized/unauthenticated/forbidden is an expired session; any other `success: false` is a server error. Points: `result.totalComputePoints`, `result.computePointsLeft`. Billing: `result.nextBillingDate` (ISO 8601), `result.currentTier`.
- **Window:** one, `.credits` (`abacus.credits`, "Credit allowance"): `(total − left) / total` — both halves reported. Reset at `nextBillingDate`. **No length is claimed** (`reportsLength: false`, 30 days as sort key): the billing date says when this cycle ends, not how long it is. CodexBar assumes the calendar month before the reset, or 30 days when there is none; both are guesses. Exhausted when nothing is left. `currentTier` is shown as the plan.
- **Figures:** a total of zero or less, or either half missing → "No limits reported" (CodexBar draws 0%). More left than the total reads as nothing used.
- **Left out, deliberately:** CodexBar's pace/reserve estimate; the credits as a separate balance line (they are not money, and the window already carries them); its Keychain cookie cache and multi-browser retry.
- **Evidence:** second-hand. The shapes come from CodexBar's Abacus provider, its docs and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/abacus-*.json`.
