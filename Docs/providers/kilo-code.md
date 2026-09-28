# Kilo Code

Profiled provider: [`Sources/Pulse/Providers/Profiled/KiloCodeUsageService.swift`](../../Sources/Pulse/Providers/Profiled/KiloCodeUsageService.swift). User setup: [../setup/kilo-code.md](../setup/kilo-code.md).

- **Credential:** `apiKey(optional: true)`. The pasted key first (refused → "That key was refused"); with none, `kilo.access` from the Kilo CLI's `~/.local/share/kilo/auth.json` (refused → "The saved login has expired"). No file → "Add an API key"; a file with no token → "Sign in with this service's own app…". The CLI file is only read.
- **Route:** one tRPC batch, `GET https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState?batch=1&input={"0":{"json":null},"1":{"json":null}}`, bearer token, 15 s timeout.
- **Reply:** a JSON array (or an object keyed `"0"`, `"1"`) of `{ result: { data } }`, where `data` may be wrapped as `{ json: … }`. A per-procedure `{ error }` is a refused credential if it says `UNAUTHORIZED`/`FORBIDDEN`, otherwise "Couldn't read the reply".
  - `user.getCreditBlocks`: `{ creditBlocks: [{ amount_mUsd, balance_mUsd, expiry_date, … }], totalBalance_mUsd }`. `_mUsd` is micro-dollars.
  - `kiloPass.getState`: `{ subscription: { tier, currentPeriodUsageUsd, currentPeriodBaseCreditsUsd, currentPeriodBonusCreditsUsd, nextBillingAt } | null }`.
- **Balance:** `totalBalance_mUsd / 1e6`, or the sum of `creditBlocks[].balance_mUsd` when the total is absent; USD. Shown as `creditBalance` / `creditRemaining`, `reportsSpendableBalance: true`. Negative or non-finite is left off.
- **Window:** the Kilo Pass period, `.credits`: `usedFraction = currentPeriodUsageUsd / (currentPeriodBaseCreditsUsd + currentPeriodBonusCreditsUsd)`, both reported (a missing bonus counts as none). Resets at `nextBillingAt`; the period's length is not stated, so 30 days is a sort key only (`reportsLength: false`). A size of zero, or a missing used/base figure, draws nothing.
- **Plan:** `tier_19`/`tier_49`/`tier_199` → Starter / Pro / Expert; any other tier with a subscription → "Kilo Pass"; no subscription → none.
- **Left out:** CodexBar's ring from the credit blocks (sum of `amount_mUsd` against sum of `balance_mUsd`) — the blocks start and expire at different times, so their sum is not an allowance Kilo sells, and the balance is shown instead; its many fallback key names (`usedCredits`, `amountCents`, …), which have never been seen in a Kilo reply; auto top-up state (`user.getAutoTopUpPaymentMethod`); organizations and the `X-KILOCODE-ORGANIZATIONID` header, which need an organization picker Pulse doesn't have.
- **Evidence:** second-hand. The shape comes from CodexBar's Kilo provider, `docs/kilo.md` and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/kilo-code-trpc-batch.json`.
