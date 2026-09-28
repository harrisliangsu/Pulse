# Factory

Profiled provider: [`Sources/Pulse/Providers/Profiled/FactoryUsageService.swift`](../../Sources/Pulse/Providers/Profiled/FactoryUsageService.swift). User setup: [../setup/factory.md](../setup/factory.md).

- **Credential:** an API key the user pastes (`fk-…`, from app.factory.ai → Settings → API keys), sent as a bearer token. Nothing is read from this Mac; `~/.factory` is only a presence hint for the chooser.
- **Headers:** `Authorization`, `Accept`, and the three Factory's web app sends — `x-factory-client: web-app`, `Origin`/`Referer: https://app.factory.ai`. Only ever to `api.factory.ai`.
- **Route**, in order:
  1. `GET https://api.factory.ai/api/app/auth/me` — `organization.subscription.orbSubscription.plan.name` (else `factoryTier`, capitalised) as the plan; `userProfile.id` for step 3. Its status decides whether the key is refused.
  2. `GET https://api.factory.ai/api/billing/limits` — read only when `usesTokenRateLimitsBilling` is `true` and `limits` is present. Anything else, a failed request included, falls through to step 3, as Factory's own app does.
  3. `GET https://api.factory.ai/api/organization/subscription/usage?useCache=true&userId=<id>` — the older Standard/Premium billing.
- **Reply (limits):** `{ usesTokenRateLimitsBilling, limits: { standard: Pool, core?: Pool }, extraUsageBalanceCents, extraUsageAllowed }`, where a pool is `{ fiveHour, weekly, monthly }` and each is `{ usedPercent, windowEnd?, secondsRemaining? }`. `windowEnd` arrives as seconds, milliseconds (anything over 10¹²), either in a string, or ISO 8601.
- **Windows (limits):** `fiveHour` → `.fiveHour` (5 h), `weekly` → `.weekly` (7 d), `monthly` → `.monthly`, a billing month, so 30 days is a sort key only (`reportsLength: false`). Standard unscoped first; Core after it with `scope: "Core"`, and only when one of its windows has a figure above zero or a clock (CodexBar's rule — an empty pool with no clock is one the account isn't using). Reset: `now + secondsRemaining` when positive, else `windowEnd` when still ahead.
- **Balance:** `extraUsageBalanceCents / 100` as USD, `creditBalance` + `creditRemaining`, shown when the account may buy extra usage or holds some. The reply names no currency; USD is from the field's name and Factory's pricing — unverified. `reportsSpendableBalance` stays `false`: the balance is overflow spent only once the limits are, the limits are the reading, and Droid spends them from this Mac — so Factory is paced as a watched provider, not as a prepaid wallet, and gets no "warn me below" line.
- **Reply (older billing):** `{ usage: { startDate, endDate, standard, premium } }`, dates in milliseconds, each pool `{ userTokens, totalAllowance, usedRatio }`. Each becomes `.monthly` scoped `"Standard"`/`"Premium"`, reset at `endDate`. The length is claimed only when both `startDate` and `endDate` are given.
- **Figures (older billing):** `usedRatio` on a 0…1 scale (a hair either side clamped). A zero ratio beside tokens used and a real allowance is read as Factory's cache lagging, and `userTokens / totalAllowance` is used instead — CodexBar's rule. Otherwise the counts are used only when both are reported and the allowance is a real one.

## Left out, deliberately

- **A window whose stated end has passed** (`windowEnd` behind now, no `secondsRemaining`). CodexBar draws it as 0% because Factory's page does; here the figure belongs to a window that is over, so it is left off until Factory states the next one.
- **"Unlimited" allowances** (over 10¹² tokens). CodexBar draws usage against a 100 M reference it chose; no ring here.
- **A `usedRatio` above 1 read as a percentage** when the allowance is missing. The scale is CodexBar's guess; not read.
- **A zero ratio with no allowance** — a pool the plan doesn't have, not a pool at 0%.
- **`overagePreference`**, the org's name, the email: not usage.
- **CodexBar's other routes**: browser cookies across three Factory hosts, WorkOS refresh tokens minted from `localStorage` or cookies, a stored session file, `FACTORY_API_KEY` / `~/.factory/.env`. Minting tokens writes a session Pulse would then have to keep alive; the pasted key needs none of it.

## Evidence

Second-hand. The shapes come from CodexBar's Factory provider and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/factory-auth-me.json`, `factory-billing-limits.json`, `factory-subscription-usage.json`.
