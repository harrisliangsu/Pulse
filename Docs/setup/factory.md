# Set up Factory in Pulse

Pulse shows the usage limits on your Factory (Droid) account. Which ones depends on how the account is billed:

- **Token rate limits** — a 5-hour, a weekly and a monthly limit, each as the percentage Factory reports. If your plan also has a **Core** pool, its three limits appear beside them, marked "Core". Extra-usage credit you have bought shows as a balance.
- **Standard and Premium tokens** (older plans) — how much of each allowance is used this billing period.

## What you need

A Factory account and an API key for it.

## Steps

1. Sign in at [app.factory.ai](https://app.factory.ai), open **Settings → API keys**, and create a key. It starts with `fk-`.
2. In Pulse: **Settings → Accounts → Factory**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists each limit and when it resets.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from app.factory.ai. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Factory sent something Pulse doesn't recognize, or the account has no limits right now. A limit whose window has just ended disappears until Factory reports the next one. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Factory's own service (`api.factory.ai`) when Pulse checks your usage. Pulse reads your plan's name, your limits and your extra-usage balance; it doesn't read your conversations or change anything on the account.
