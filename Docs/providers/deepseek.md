# DeepSeek

| `Provider` | Ring name | Host | Icon |
|---|---|---|---|
| `.deepSeek` | DeepSeek | `https://api.deepseek.com` | `deepseek` |

Service: [`../../Sources/Pulse/Providers/DeepSeekUsageService.swift`](../../Sources/Pulse/Providers/DeepSeekUsageService.swift). The web console (usage history, and the balance without a key): [`../../Sources/Pulse/Providers/DeepSeekConsole.swift`](../../Sources/Pulse/Providers/DeepSeekConsole.swift), Settings group [`DeepSeekConsoleGroup`](../../Sources/Pulse/Settings/DeepSeekConsoleGroup.swift). The denominator modes and the watched mark: [`../../Sources/Pulse/Providers/DeepSeekBalanceBasis.swift`](../../Sources/Pulse/Providers/DeepSeekBalanceBasis.swift).

## Verified against a live account

Unlike [command-code.md](command-code.md), this one was. `GET /user/balance` was called with a real key on 2026-09-10 and answered `200` with exactly the documented body; a deliberately wrong key answered `401`. The service was then run end to end through all three modes against that account and its readings checked. The fixtures under `Tests/PulseTests/Fixtures/deepseek-*.json` are written to that confirmed shape rather than containing anybody's balance.

## The route

One route, and it is **documented** — it sits in DeepSeek's own API reference beside chat completions, not in the undocumented account endpoints most of this directory reads.

```
GET https://api.deepseek.com/user/balance
Authorization: Bearer <key>
```

```json
{ "is_available": true,
  "balance_infos": [ { "currency": "CNY", "total_balance": "110.00",
                       "granted_balance": "10.00",
                       "topped_up_balance": "100.00" } ] }
```

Status handling is the ordinary one: `401`/`403` → `.apiKeyRefused`, `429` → `.rateLimited`, anything else → `.serverError`.

**Every figure is a string, including the money.** Parsed at the boundary so nothing downstream knows. A field that is absent or unparseable is **absent, not zero** — the rule the rest of this directory learned the hard way, and it bites hardest here: a balance read as zero is a full red ring and a notification announcing an account as spent.

## Credential

Two, each in its own slot of `APIKeyStore`, so neither replaces the other:

1. **A key pasted into Settings** (`deepSeek`). There is nothing to borrow — DeepSeek's key lives on its web console and no CLI on this Mac stores one. It reads the balance, and wins whenever it answers.
2. **The console's sign-in** (`deepSeek#console`), read from a Chromium browser in Settings › DeepSeek › **DeepSeek console** ([below](#the-console-usage-history-and-a-balance-without-a-key)). It reads the usage history, and the balance when there is no key or the key route came back `.apiKeyRefused` / `.unreachable` / `.serverError` / `.unreadableReply` — reading `origin = .webSession`.

The chooser offers DeepSeek unchecked, without a detected hint.

## There is no allowance, so the ring has no denominator

*Since generalized:* these three modes are now every API account's rule — see `BalanceRing` and [README.md](README.md#subscriptions-and-api-accounts). DeepSeek keeps its own settings (`deepSeekBasis`, `deepSeekBudget`) and its own mark file, and makes its window through the same `BalanceRing.window`.

**This is the first provider Pulse carries that reports no percentage at all.** The reply says how much money is left and stops. There is no quota, no window, no reset, and no spend-history endpoint anywhere in the API (the history Pulse shows comes from the web console, with its own sign-in — [below](#the-console-usage-history-and-a-balance-without-a-key)). Every provider before it reported at least one fraction.

A ring needs a denominator, and there are exactly three places one can come from — which is why `BalanceBasis` has exactly three cases and the user picks between them in DeepSeek's settings pane.

| Mode | Denominator | Ring |
|---|---|---|
| `sinceTopUp` **(default)** | The highest balance Pulse has watched | `(peak − balance) / peak` |
| `balanceOnly` | None | No window; the rail draws the money |
| `budget` | A figure the reader typed | `(budget − balance) / budget` |

Both fractions carry a `UsageWindow.Estimate` naming where the number came from — `sinceTopUp` or `yourBudget` — which the card renders after the name ("余额 · 自上次充值") and `--json` reports as the stable token `estimatedFrom`.

**Not `scope`.** That was the first attempt and it shipped wrong for an afternoon: `scope` is a product name and [../json-output.md](../json-output.md) promises it reads the same in every language, so a localized "since top-up" in it broke any script matching on it the moment the reader switched language. The same trap `.localized` in a contract field is always going to be.

### `sinceTopUp` is measured, not inferred

This is the whole reason it is the default. Pulse reads the balance every refresh — 2 to 5 minutes while the panel is shown, since DeepSeek's spending is not visible on this Mac (`AdaptiveRefresh.unwatchedCeiling`), up to 30 while it is hidden — and remembers the highest it has seen. **A balance that goes up can only be a top-up**, so that resets the mark and the ring starts from full again. Nothing here is a guess about DeepSeek's pricing, a table of plans, or a number anyone typed. Contrast [command-code.md](command-code.md), where the plan grant genuinely is a table in a client.

What it costs is the first run: a Mac that has never watched this account has no mark, so the first reading becomes one and the ring reads 0% until money is actually spent. That is a true statement about what Pulse has seen. A peak of zero draws no window at all — an account that has never had credit is not one that has spent it.

### "No fraction" is not "no reading"

Three separate places read `usedFraction == nil` (or `headline == nil`) as *nothing came back*, which was sound while every provider reported a percentage. On `balanceOnly` all three were wrong about a perfectly good reading, and each had to be pointed at whether there is a reading rather than whether there is a fraction:

- `UsageCache.reconciled` threw the reading away and handed back the previous one, so the setting appeared to do nothing.
- The hover card drew a bubble with only the provider's name in it.
- The rail drew the icon and the figure at 35% and 40% opacity — the dimming that means "Pulse has no data for this one".

`UsageRingView` now takes `hasReading` rather than inferring it, and the rail's label dims only when it has neither a percentage nor a figure.

### The card shows the money

`balanceOnly` produces a reading whose body is nothing but a balance, and the card's body is otherwise limits, an unavailability message and a footnote — so hovering it drew a bubble with only the provider's name in it, which reads as a card that failed to load. Where a provider reports money and no allowance the money *is* the reading, so the card says it as a plain figure. No bar: a bar at zero beside a healthy balance reads as an empty account. No explanatory line either — it said the provider reports no limit, which the card has already made obvious by having nothing else on it.

### The ring gets a glance, the card keeps the figure

The rail's label is budgeted for "100%" — 38pt. Money is bounded by nothing: ¥5,000.00 wants 64pt and a reader outside China looking at a CNY account gets "CN¥5,000.00" at 83pt. `minimumScaleFactor` gives up at 0.6 and those need 0.56 and 0.43, so both were truncated on screen.

`CreditAmount.railText(locale:)` is the short form — `¥9.4`, `¥5k`, `¥123k`, `$1.2M` — with the **narrow** symbol, which is what turns "CN¥" back into "¥". It is **truncated, never rounded**: a balance shown as more than it is is the wrong way to be wrong, and it settles the rollover for free (999,999 is `¥999k`, not the `¥1,000k` that rounding to one place produced). Cents survive below a hundred, where they are the part somebody might be watching.

The exact figure is a hover away and is also in Settings. `RailMoneyTests` pins the forms and measures every one of them against the rail's own thickness.

### A reading with no windows is still a reading

`balanceOnly` is the first **complete** answer Pulse has ever produced with no windows in it. `UsageCache.reconciled` tested `!windows.isEmpty` to mean "this fetch went wrong" — a fair assumption while every service with nothing to report returned `.noLimitsReported` — so it kept handing back the previous reading and switching the setting appeared to do nothing at all. The test is now `ProviderUsage.reportsSomething`: a balance is an answer. A reading carrying neither windows nor a balance is still a failure to fall back from, and `UsageCacheTests` pins both halves.

**The read path needed it too, and was missed the first time.** `reading(for:)` had the same `!windows.isEmpty` guard, so a banked balance-only reading could be written and never come back out: blank through the first round trip after launch, no fallback when a fetch failed, and `--json` reporting a null balance. `Stored` also gained `creditRemaining`, or the restored reading falls back to the long currency string on the rail.

Marks live in `deepseek-baseline.json` in Pulse's Application Support folder, **one per currency**, written off the main thread on a serial queue — the same arrangement `UsageAlerts` writes its memory with, and for the same reason: this is written on every pass. The mark is advanced on every reading whichever mode is in force, so switching to `sinceTopUp` later finds a peak already there rather than starting over from whatever the balance happens to be that afternoon.

### `budget` is the reader's own line

Blank, zero or negative leaves the mode with no denominator, which draws the balance alone rather than a fraction of a number nobody gave. A balance above the budget is **0% used**, not a negative fraction.

## Warn me below

`AppSettings.lowBalanceAlerts` holds a figure per account, and DeepSeek's settings pane offers the field because `Provider.reportsSpendableBalance` is true for it. Off until a figure is entered, like every other alert. The rule, the memory and why it is money rather than a percentage: [../notifications.md](../notifications.md).

This is the reason `ProviderUsage.creditRemaining` exists alongside `creditBalance`. The latter is a display string and is sometimes prose — Codex's says "Unlimited" — so nothing may be decided from it; the former is a number and the currency it is denominated in, so ¥ is never compared against $.

## Notifications: prepaid credit is not a limit

Two rules in `AlertMemory` had to learn that, because `Kind.balance` breaks assumptions both of them rested on:

- **A balance never resets.** `resetsAt` is always nil, so the reset test collapsed to "the fraction dropped forty points" — and on DeepSeek that fraction is a *setting*: both modes emit the window id `balance`, so switching "My budget" to "Since top-up" moved it forty points with the money untouched and posted "This limit has reset" within a second of touching the picker.
- **Only the provider may call it spent.** The step rule reaches 100 from the arithmetic, and here the arithmetic is a clamp against a denominator Pulse watched or the reader typed. A ¥100 full tank with the balance at zero announced "This limit is spent" while `is_available` was true. A `.balance` row is now capped at 99 unless `isExhausted` says otherwise.

## `is_available` is the only thing that may say "spent"

DeepSeek's own flag for "this balance can no longer pay for a call". Nothing else sets `isExhausted` — in particular a generous budget can put the ring near the top while the account is perfectly able to pay, and that is the reader's line rather than DeepSeek's verdict. [../notifications.md](../notifications.md)

## `kind` is `.balance`, not `.spend`

Prepaid credit is **not a limit**: there is no ceiling to reach and no window to turn over. `.spend` made the row read "Spend limit", which put the word *limit* on something that has none. `reportsLength` is false and `resetsAt` is nil, always — the seconds exist only to sort the row. `--json` reports the kind as `balance`.

## The console: usage history, and a balance without a key

*Until 2026-10-03 this section said "no usage history" — the routes were known and the credential was out of reach, because it lives in `localStorage` and Pulse read only cookies. `ChromiumLocalStorage` (written for Devin) removed that obstacle.*

**The credential.** The console's routes want `Authorization: Bearer <userToken>`, its own login token; an API key is refused (`40003`). The token is in **`localStorage`** for `https://platform.deepseek.com`, key `userToken`, wrapped by the console's storage class — `{"value":"<token>","__version":"0"}`, with `"value":null` once signed out (`DeepSeekConsole.token(fromStorage:)`). Settings › **DeepSeek console** › **Read** finds it in the first Chromium browser that has one, default first, with **no keychain prompt** (`localStorage` is not encrypted), and keeps it in `deepSeek#console`. Whether one is kept is cached in memory (`DeepSeekConsole.hasSession`, refreshed in `UsageStore.loadAPIKeys`), because the detailed card asks every frame. When the console turns the kept token away, the browser is read once more and a **different** token found there replaces it — on the history read (`DeepSeekConsoleHistory`) and on the balance read (`DeepSeekConsole.balanceRenewing`), so a lapsed sign-in with no key mends itself on the next refresh, and one that cannot be mended reads `.sessionExpired`, not "add a key"; the same token, or none, is a sign-out, and the card says to read it again in Settings. Safari and Firefox are not read: neither keeps `localStorage` in a LevelDB.

**The envelope.** Every route answers HTTP 200 with `{code, msg, data: {biz_code, biz_msg, biz_data}}` — **including a refused token**: `{"code":40002,"msg":"Missing Token"}`, `{"code":40003,"msg":"Authorization Failed (invalid token)"}`. A `code` in 40000–40099 is a sign-out, any other non-zero `code` or `biz_code` a failure (`DeepSeekConsole.outcome`). HTTP 401 is a sign-out; **a 403 is not** — it is the WAF in front of the console, and treating it as one would swap the kept sign-in for whatever the browser holds. Reachable without a browser: the console's pages sit behind an AWS WAF challenge, its `/api/` routes do not (checked with curl, 2026-10-03).

**Routes** (shapes from the console's bundle, `main.417f9e6095.js` and its chunks, 2026-10-03; the page's own requests to them seen answering 200 on a signed-in account):

| Route | Shape (`biz_data`) |
|---|---|
| `GET /api/v0/usage/by_api_key/amount?start=&end=&tz=` | `{start, end, bucket, models, series: [{api_key, model, buckets: [{time, usage: {PROMPT_CACHE_HIT_TOKEN, PROMPT_CACHE_MISS_TOKEN, RESPONSE_TOKEN, REQUEST}}]}]}` |
| `GET /api/v0/usage/by_api_key/cost?start=&end=&tz=` | `{start, end, bucket, models, data: [{currency, series: [{api_key, model, buckets: [{time, cost}]}]}]}` |
| `GET /api/v0/users/get_user_summary` | `{normal_wallets: [{balance, currency, token_estimation}], bonus_wallets: […], total_costs: [{currency, amount}], monthly_usage, total_usage, current_token, total_available_token_estimation}` |

`start`/`end` are seconds; `tz` is the zone offset in seconds, **a whole number of hours** — the console floors it and moves the remainder into `start`/`end`, and `DeepSeekConsole.range` does the same, so a +5:30 reader gets the console's own buckets. `time` is a bucket's start in seconds; `bucket` is its length (86,400 for days; the console treats under a day as hours). The token counts are numbers (the console adds them); `cost` and the wallet balances go into the console's decimal type, so they are decoded as **either a number or a string** (`DeepSeekConsole.Figure`), and absent is nil, never zero — as is anything not finite or beyond 10¹⁵ (`"nan"`, `"inf"` parse as Doubles and trap when made Ints). A bucket is put on the local day of its **middle**, not its start: the buckets follow the offset in force now, so across a daylight-saving change a day's start sits an hour off midnight.

**The history** is the console's own "last 30 days" — today and the twenty-nine before, `start` = local midnight 29 days ago, `end` = tomorrow's midnight, which is the request the page itself makes. Amount and cost are asked together; the series are per key and model, and **every key is added up**, so it is the whole account. Per day and model: cache-miss input → `input`, cache hits → `cacheRead`, response → `output`; DeepSeek writes no cache, so `cacheWrite` is 0. The card's per-model cache hit rate falls out of that. `REQUEST` is not kept — nothing on the card shows a request count. The ledger is `origin = .providerLogs` (whole account, priced as charged, no "≈"), with **no quarter-hour slots** and `hasAggregateTiming`: a day bucket does not say when in the day the work ran, so nothing per-hour or per-window is drawn from it. The card's footnote names the console and the 30 days.

**Money is in the account's own currency.** `UsageLedger.currency` exists for this — every other history is in dollars — and both money figures on the cards (`AccountUsageCard.money(_:currency:)`) follow it, so a CNY account reads ¥ and not $. The cost reply is per currency and the two cannot be added: the ledger carries one — the reader's choice for the ring (`deepSeekCurrency`) **if anything was charged in it**, else the first the reply lists with any money in it, else the choice, else the first. Tokens are counted whichever currency paid for them. **No money in the reply at all** (no purse) makes the ledger `.providerStatistics`: tokens only, never a "$0.00" bill. An amount under a cent reads "< ¥0.01" (`AccountUsageCard.money`), not "¥0.00".

**The balance without a key** comes from the summary's wallets: per currency, `normal_wallets` is topped up, `bonus_wallets` granted, their sum the total — handed to the key route's own rule as a `Reply`, so the ring, the marks and the alerts are the same whichever credential answered. The summary states no `is_available`, so a console reading can **never** be marked spent. `token_estimation` is the console's guess at tokens left and is not shown.

**Reads.** `DeepSeekConsoleHistory` shares one read between the card, Settings and the warm-up `UsageStore.loadAPIKeys` starts while DeepSeek is on and a sign-in is kept, and reuses any outcome — a refusal too, so a dead sign-in is not asked again at every settings change — for 60 seconds; the card keeps its own five minutes on top (`CardLedgers.lifetime`), read again at once when the kept sign-in or the currency changes (`CardLedgers.inputs`). Two requests a read — not paged, unlike OpenCode's log.

**Verified** against a live account on 2026-10-03 only as far as the console's own page goes: signed in, `/usage` asked exactly the range above (`start=1788451200&end=1791043200&tz=28800`, 4 Sep–4 Oct at +08:00) and both routes answered 200, alongside the summary; the page then read ¥1.31, 592 requests, 1,419,424 tokens for the 30 days across `deepseek-flash`, `deepseek-v4-flash` and `deepseek-v4-pro`. The response bodies could not be captured, so the decoders are written to the bundle's mapping rather than to a captured reply, and `DeepSeekConsoleTests` uses synthetic fixtures in that shape. The same account was then read through Pulse (Settings › DeepSeek console › Read, from Chrome) and its figures matched the page's.

Not read: `/api/v0/usage/export` (a spreadsheet), `/users/get_api_keys`, `/api/v0/users/set_alert_bound` (DeepSeek's own server-side low-balance alert; Pulse's [Warn me below](#warn-me-below) is the local equivalent and does not touch it).

## Service status

Settings › DeepSeek › **Service status** (`ServiceStatus.flashcat`, `ServiceStatusGroup`, `StatusPage.deepSeek`): every component status.deepseek.com shows — DeepSeek V4 Pro API, V4.1 Flash API, and the chat section's chat, file upload and search as of 2026-10-04 — each with the state now, a bar a day for 90 days and the page's uptime, as on [codex.md](codex.md#service-status) and [claude-code.md](claude-code.md#service-status). Requested 2026-10-04.

**Read out of the page, because there is no feed.** The page is Flashcat's (Flashduty); `/api/v2/summary.json` is a 404, and Flashcat's open API needs an account key. The page is a Next.js app: its data travels in `self.__next_f.push([1,"…"])` script chunks which, joined, are lines of `id:JSON`. Two lines carry an `initialData` object — `page` (`components[]` with `component_id`, `name`, `section_id`, `status`, `order_id`, `hide_all`; `sections[]`) and the history (`component_impacts[]` with `start_at_seconds`, `end_at_seconds`, `status`; `component_uptimes[]` with a numeric `uptime` and `available_since_seconds`). Nothing else on the page is read. **A redesign that moves them is no reading** — the pane says it couldn't read the page — never "all clear". The fixture is the whole page as captured.

**The model is incident.io's**: a day takes the worst impact overlapping it; before `available_since_seconds` it has no record. States: `degraded`, `partial_outage`, `full_outage`, `maintenance` (Flashcat's spellings). The state now is the component's own `status` when the page gives one — null while operational, as far as has been seen — else any impact still open. No live outage has been seen; that part follows the model, not an observation.

**Local days.** The server draws its first pass in UTC, then the page redraws in the viewer's time zone once it loads. Pulse matches what the reader sees: in UTC+8 on 2026-10-04 all five rows agreed bar for bar with the browser (`ServiceStatusTests`), and the UTC pass agreed with the server's HTML. A section's own row is an aggregate and is not drawn, as with OpenAI's groups.

**Colours are the page's**: operational `#22C55E`, degraded `#EAB308`, partial `#F97316`, full `#EF4444`, rounded bars; maintenance `#3B82F6` is a guess from the same Tailwind set.

**Notifications cover the API rows only** — `name` contains "API". Pulse reads the API account, the API rows are named after the model and a new model is a new row, and the chat site is not the API. [../notifications.md](../notifications.md)

## Currencies

`balance_infos` is an **array** and an account can hold both CNY and USD. They cannot be added, and Pulse will not pick a "main" one by comparing figures across currencies — ¥100 against $10 is not a comparison. The ring follows the reader's choice if they made one, else the first entry with money in it, else the first entry at all. `creditBalance` is formatted in the currency the purse is actually priced in, not the reader's locale.
