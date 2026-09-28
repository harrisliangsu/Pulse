# Set up Aixy in Pulse

Pulse shows the budgets that apply to one Aixy key — set on the key itself, or on its user, team, project or organization — as rings of the amount used against each budget's limit. Where two budgets share a period, the one that binds is shown.

## What you need

An Aixy project API key, on the hosted gateway at aixy-gateway.com, with at least one budget that applies to it.

## Steps

1. Sign in to Aixy and create or copy the project API key your workload uses.
2. In Pulse: **Settings → Accounts → Aixy**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists a daily, weekly or monthly limit — or a spend limit for a lifetime budget — with the reset Aixy reports.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a project API key from Aixy. |
| That key was refused. Check it in Settings. | The key is disabled, revoked or expired. Paste an active one. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| No limits reported. | No budget applies to this key, or Aixy doesn't know any budget's balance right now. |
| Couldn't read the reply. | Aixy sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Aixy's hosted gateway (`api.aixy-gateway.com`) when Pulse checks your usage. No model request is made.
