# Set up MiniMax in Pulse

MiniMax sells the same product on two sites: [minimax.io](https://platform.minimax.io) (international) and [minimaxi.com](https://platform.minimaxi.com) (mainland China). They are **separate accounts with separate keys** — a key from one is refused by the other — so Pulse asks which site yours is from.

Pulse shows your Coding Plan's limit windows (typically a short rolling window plus a weekly one).

## What you need

A MiniMax account with a Coding Plan subscription on either site. The mainland site needs real-name verification, as mainland accounts do.

## Steps

1. Create a key on your site:
   - **minimax.io:** sign in at [platform.minimax.io](https://platform.minimax.io), add a payment method if asked, then go to **API Keys** and create a new key.
   - **minimaxi.com:** sign in at [platform.minimaxi.com](https://platform.minimaxi.com), open **接口密钥** (API Key) in the left sidebar, then **创建新的 API Key** (Create New API Key). <!-- unverified: exact menu labels, taken from a third-party walkthrough rather than a directly fetched rendered page (the console is a JS app) -->

   Copy the key immediately — it's only shown once.
2. In Pulse: **Settings → MiniMax**. Turn on **Show in panel**. Under **Connection**, choose your **Site**, paste the key into **API key** and click **Save**.
3. Within a few seconds the MiniMax ring appears with your plan's windows.

Each site keeps its own key, so switching **Site** later does not lose the one you saved for the other. Pulse watches one site at a time.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from the site chosen under **Site**. |
| That key was refused. Check it in Settings. | Often means the key is from the *other* site — check **Site**. Otherwise the key may be wrong, revoked, or the account may lack a Coding Plan. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | The provider sent something Pulse doesn't recognize, or this account currently has no plan windows to report. Try again later. |

## Earlier versions

In earlier versions of Pulse, the two sites were separate providers, **MiniMax** and **MiniMax CN**. Updating keeps both keys: a MiniMax CN key becomes the minimaxi.com site's key, and if MiniMax CN was the one you had switched on, the site is set to minimaxi.com and its ring keeps its place and settings.

## What Pulse reads

Each key is stored encrypted on this Mac. The minimax.io key is sent only to minimax.io's API, and the minimaxi.com key only to minimaxi.com's. They are never crossed.
