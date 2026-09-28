# Set up Warp in Pulse

Pulse shows your Warp plan's credits for the period, as the share used with the refill date Warp reports, and any add-on credits on top as a second ring with when the soonest of them expire.

## What you need

A Warp account with AI credits, and a Warp API key.

## Steps

1. In Warp, open **Settings → Platform → API Keys** and create a key (it starts with `wk-`). Warp's guide: [API keys](https://docs.warp.dev/reference/cli/api-keys).
2. In Pulse: **Settings → Accounts → Warp**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears. The card shows "Credit allowance" for the plan and "Top-up pack" for add-on credits, if you have any.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from Warp's settings. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| No limits reported. | Your plan is unlimited, or Warp reported no credit figures. There is nothing to draw a ring for. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Warp sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Warp's own service (`app.warp.dev`) when Pulse checks your usage. Pulse sends the same read-only question Warp's app asks about your credit limit; it changes nothing on your account.
