# Set up ZenMux in Pulse

Pulse shows your ZenMux subscription's rolling 5-hour and 7-day quotas, each as the percentage ZenMux reports, and your pay-as-you-go balance.

## What you need

A ZenMux subscription and a **Management API key**. Ordinary ZenMux API keys — the ones you use for model calls — are refused by the endpoints Pulse reads.

## Steps

1. Open the [ZenMux Management Console](https://zenmux.ai/platform/management) and create a Management API key.
2. In Pulse: **Settings → Accounts → ZenMux**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the pane lists the 5-hour and weekly limits with their resets, your plan, and the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a Management API key. |
| That key was refused. Check it in Settings. | Make sure it is a Management key, not an ordinary API key, and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | ZenMux sent something Pulse doesn't recognize, or the account has no subscription quota right now. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to ZenMux's own service (`zenmux.ai`) when Pulse checks your usage.
