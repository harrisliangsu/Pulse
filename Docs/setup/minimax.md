# Set up MiniMax / MiniMax CN in Pulse

MiniMax (international) and MiniMax CN are the same product on two storefronts, and they're **separate accounts with separate keys** — a key for one is refused by the other. Pulse gives each its own row, so use the one that matches where you actually subscribed.

For either one, Pulse shows your Coding Plan's limit windows (typically a short rolling window plus a weekly one).

## MiniMax (international)

### What you need
A MiniMax account with a Coding Plan subscription, at [platform.minimax.io](https://platform.minimax.io).

### Steps
1. Sign in at [platform.minimax.io](https://platform.minimax.io), add a payment method if asked, then go to **API Keys** and create a new key. Copy it immediately — it's only shown once.
2. In Pulse: **Settings → Accounts → MiniMax**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the MiniMax ring appears with your plan's windows.

## MiniMax CN

### What you need
A MiniMax account with a Coding Plan subscription, at [platform.minimaxi.com](https://platform.minimaxi.com) — this needs real-name verification, as mainland accounts do.

### Steps
1. Sign in at [platform.minimaxi.com](https://platform.minimaxi.com), open **接口密钥** (API Key) in the left sidebar, then **创建新的 API Key** (Create New API Key). Copy it immediately — it's only shown once. <!-- unverified: exact menu labels, taken from a third-party walkthrough rather than a directly fetched rendered page (the console is a JS app) -->
2. In Pulse: **Settings → Accounts → MiniMax CN**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the MiniMax CN ring appears with your plan's windows.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from the matching console above. |
| That key was refused. Check it in Settings. | Often means the key is from the *other* storefront — a MiniMax key pasted into MiniMax CN (or vice versa) is refused. Otherwise the key may be wrong, revoked, or the account may lack a Coding Plan. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | The provider sent something Pulse doesn't recognize, or this account currently has no plan windows to report. Try again later. |

## What Pulse reads

Each key is stored encrypted on this Mac. A MiniMax key is sent only to platform.minimax.io's API; a MiniMax CN key is sent only to platform.minimaxi.com's API. They are never crossed.
