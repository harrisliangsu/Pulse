# Set up ClawRouter in Pulse

Pulse shows the monthly budget on your ClawRouter key's policy, as a ring of what has been spent this month against the budget.

## What you need

A ClawRouter key on the hosted service whose policy has a monthly budget. An unmetered policy has no budget and no ring.

## Steps

1. Create or copy your ClawRouter key at [clawrouter.openclaw.ai](https://clawrouter.openclaw.ai).
2. In Pulse: **Settings → Accounts → ClawRouter**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the pane lists the monthly limit.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste your ClawRouter key. |
| That key was refused. Check it in Settings. | Check the key and that its policy is active, then paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| No limits reported. | The key's policy is unmetered — it has no monthly budget. |
| Couldn't read the reply. | ClawRouter sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to ClawRouter's hosted service (`clawrouter.openclaw.ai`) when Pulse checks your usage. That endpoint returns accounting figures only, never prompts or responses.
