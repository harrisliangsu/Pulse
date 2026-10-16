# MiniMax

One provider, two sites: [`MiniMaxUsageService.swift`](../../Sources/Pulse/Providers/MiniMaxUsageService.swift).

| Site (`MiniMaxSite`) | Picker | Host | Key |
|---|---|---|---|
| `.international` | minimax.io | `https://api.minimax.io` | the provider's own entry |
| `.china` | minimaxi.com | `https://api.minimaxi.com` | slot `minimaxi.com` |

Same product, two storefronts, two accounts; a key for one is refused by the other. **The site is a setting** (`AppSettings.minimaxSite`, Settings → MiniMax → Connection → *Site*, above the key), as Qoder's and StepFun's are. **Each site keeps its own key** (`MiniMaxSite.keySlot`, read through `AppSettings.keySlot(for:)` by the store, the services and the key field): unlike Qoder's session, a pasted key cannot be read back from a browser, so choosing the other site must not throw it away. The key field and its subtitle follow the chosen site. Changing the site goes through `onChange`, which reloads the keys. **The two sites never stand in for each other's figures**: every reading carries a scope of the site's host and a SHA-256 of the key (`MiniMaxUsageService.scope`, `requiresScopeMatch`), so a failed read on one site does not fall back to the other's cached figures; and a site change drops the old site's reading from the panel and from disk (`UsageStore.settingsChanged`, `UsageCache.forget` — Qoder's and StepFun's too), so `--json` and the next launch don't show it either. `MiniMaxSiteScopeTests`.

**There were two providers until 2026-10-15, MiniMax and MiniMax CN** (`.minimaxCN`). `MiniMaxMerge` folds the second into the first once, at launch, before settings are read: its key moves sealed to the `minimaxi.com` slot (`APIKeyStore.moveRetiredEntry`); where MiniMax CN was on and MiniMax was not, the site becomes `minimaxi.com` and its ring settings (place on the rail, colour, mark, pinned limit — the window id's `minimaxCN.` prefix is rewritten) become MiniMax's; otherwise MiniMax's stay and MiniMax CN's fill only what MiniMax lacked. Cached readings under `minimaxCN` are keyed by plain strings and are simply never asked for again. `MiniMaxMergeTests`.

Extra accounts are not supported, so the two sites cannot be watched at once. `keepsLocalTranscripts` is false; **the usage history is MiniMax Code's**, read from this Mac (`SpendAgent.mcode`, which borrows MiniMax's mark — [../token-spend-sources.md](../token-spend-sources.md)): every model the app answered with, routed ones too, as Command Code's are, and only with Token spend on. The detailed card and the settings pane's **Usage history** both show it. No first-run file detection.

## Route

`GET {host}/v1/token_plan/remains` with the key as a bearer token, falling back to the older `/v1/api/openplatform/coding_plan/remains` on **any** failure, not only a 404 — an account on the older plan answers 401 on the current path.

Undocumented; can change without notice. Parsing follows CodexBar’s written account of the reply.

The **first** failure reason is kept, not the last: a `.apiKeyRefused` from the current path must not be overwritten by a later miss.

`base_resp.status_code` is the service’s verdict and is **not** the HTTP status. A refused key is a perfectly good HTTP 200.

## Mapping

**It reports what is left.** `current_*_remaining_percent` at 96 means 4% spent. Inversion happens here. (Copilot and Antigravity also invert remaining-style fields.)

**Every figure can be a string or a number**, the same field in different replies. CodexBar’s own two fixtures disagree (`"96"` and `75`). Reading only one shape blanks a window for whichever accounts get the other.

**Lanes exist that the subscription does not include** — status 3, nothing issued, 100% remaining, a video lane on a plan with no video. Read literally that is a ring pinned at 0% for something the account cannot use, so they are left out. The same shape covers a genuinely unlimited lane, which has no percentage worth showing either.

**`*_usage_count` is the quota that is *left*, not the quota used** — the name says the opposite of what it holds. Reading it as a spend inverts every figure on the card. It is the fallback when the percentages are absent, which is the shape the older endpoint returns.

The payload is not always under `data`; some replies put it at the root. Reading only `data` reported a good account as having no limits.

Each model gives up to two windows. The short one’s length is measured from its own timestamps (5 hours, in every reply seen) and is **dropped when they are absent** rather than assumed. The weekly one names its own length so it survives that.
