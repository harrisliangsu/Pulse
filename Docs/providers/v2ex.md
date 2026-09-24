# V2EX

| `Provider` | Ring name | Host | Icon |
|---|---|---|---|
| `.v2ex` | V2EX | `https://edge.v2ex.com` | `v2ex` |

Service: [`../../Sources/Pulse/Providers/V2EXUsageService.swift`](../../Sources/Pulse/Providers/V2EXUsageService.swift).

V2EX's AI Chat allowance. One of the few routes in this directory with a **published help page** behind it — [`edge.v2ex.com/help/quota`](https://edge.v2ex.com/help/quota) states the rules the numbers follow — rather than an endpoint borrowed from a product's own UI.

## Not verified against a live account

No V2EX token was used. The route, the body and the window rules are taken from V2EX's own help page and from the sample reply in [issue #40](https://github.com/qunqin24/Pulse/issues/40). The fixtures under `Tests/PulseTests/Fixtures/v2ex-*.json` are written to that shape.

## The route

```
GET https://edge.v2ex.com/api/v2/chat/quota
Authorization: Bearer <personal access token>
```

```json
{ "success": true, "message": "Current AI Chat 5h quota",
  "result": { "active": false,
              "total_tokens": 8020000, "used_tokens": 0,
              "remaining_tokens": 8020000, "used_percent": 0,
              "period_start": 0, "period_end": 0,
              "extra_usage": { "pack_count": 1, "total_tokens": 12000000,
                               "used_tokens": 34897,
                               "remaining_tokens": 11965103 } } }
```

Status handling is the ordinary one: `401`/`403` → `.apiKeyRefused`, `429` → `.rateLimited`, anything else → `.serverError`. `"success": false` over a 200 is read as `.apiKeyRefused` — the route is scoped to the token, so the one thing it can refuse is the token.

**Asking never starts a window.** V2EX's help page says so explicitly, which is what makes this safe to poll on the ordinary 2–30 minute cadence.

## The window has not started

**This is the first window Pulse carries that is not on a clock.** V2EX grants five hours' worth when it receives the reader's next message, not on the hour — so a perfectly good reading can report an allowance, its size, and no window at all:

- `active: false` → `period_start` and `period_end` are **zero**, and `resetsAt` is nil. Zero is not a date: 1 January 1970 drawn as a reset is a countdown that ran out fifty-six years ago.
- `reportsLength` is false while inactive. The five hours are real but they have not started, and a length with no reset to measure against is exactly what draws an elapsed arc for a clock that is not running. See [`README.md`](README.md#windowseconds-is-not-evidence-of-a-reported-length).
- The fraction is still drawn, because it is still true: nothing spent is 0%.

When `active` is true, `period_end` is the reset and the length is real, so the window clock and the forecast both apply.

The fraction comes from V2EX's own `used_tokens` over its own `total_tokens`, **not** from `used_percent` — that is the same figure already rounded to a whole number, and the panel does its own rounding. Rounding a rounding loses the one point that matters at the ends.

The size of a window is worked out when it starts, from the account's standing at that moment (base allowance, top-ups in the last 365 days, `$V2EX` and `$V2EX LP` holdings). Pulse reports whatever V2EX says the total is and does not reconstruct that sum.

## The extra pack is a second allowance

`extra_usage` — 额外用量, the 加油包 — is tokens bought on top. It **never expires** and is spent only once the window's allowance is gone. It is reported as its own window with `UsageWindow.Kind.topUp`:

- **Not folded into the five-hour window.** A reader whose window is spent but whose pack is full is not out of quota, and one ring reading 100% would tell them they were.
- **Not `.balance`**, which is money, and **not `.messages`**, which is Devin's count of messages. The name on the card would be wrong either way, so it is its own kind. `--json` reports the token `topUp`.
- No reset and no length. `windowSeconds` is a sort key that puts it last, because it is spent last.
- Drawn only when `pack_count > 0`. Nobody wants an empty second ring.

`Kind.topUp` joins `.balance` in two rules that assume a window is a window:

- **`UsageWindow.hasTurnedOver` excludes it.** Buying a second pack drops the fraction by more than forty points with nothing having turned over, which is precisely the shape the reset test fires on — and "this limit has reset" about a purchase is a notification for something that did not happen.
- **`UsageAlerts.step` caps it at 99 unless `isExhausted` says otherwise**, for the same reason a prepaid balance is capped: only the provider's own remainder may call it spent. [../notifications.md](../notifications.md)

## Spent comes from V2EX

`isExhausted` is set from the reported `remaining_tokens <= 0`. A field that is absent has said nothing; reading silence as zero announces an allowance spent on the strength of it. A `total_tokens` of zero is not an allowance to divide by and produces no window.

## Credential

A Personal Access Token from `v2ex.com`, pasted into Settings and kept encrypted on this Mac by `APIKeyStore`. Nothing to borrow and no discovery hint — V2EX is a website — so the row stays off until it is switched on.

## The name

**V2EX, not "AI Chat".** The allowance is granted to the V2EX account and its size is computed from what that account has done on the site — years of top-ups, and a Solana balance — so it belongs to the membership rather than to a product bought separately. Same rule as `.xiaomiMiMo` being named for the plan and `.deepSeek` for the shop.

## Not carried

- **`used_percent`.** Superseded by the exact ratio above.
- **The composition of the allowance** (base / top-up / holdings). V2EX reports the total, which is the number with a denominator in it; the breakdown is a question about the account rather than about usage.
