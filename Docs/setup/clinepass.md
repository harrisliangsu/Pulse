# Set up ClinePass in Pulse

Pulse shows your ClinePass subscription's three limits: the 5-hour window, the weekly window and the monthly allowance, each as the percentage Cline reports.

## What you need

A ClinePass subscription on your Cline account. Pay-as-you-go credit is a separate thing and isn't shown.

## Steps

1. Sign in at [app.cline.bot](https://app.cline.bot) and create an API key.
2. In Pulse: **Settings → Accounts → ClinePass**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists the three limits and when each resets.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from app.cline.bot. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Cline sent something Pulse doesn't recognize, or the account has no ClinePass limits right now. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Cline's own service (`api.cline.bot`) when Pulse checks your usage.
