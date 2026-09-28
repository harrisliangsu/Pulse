# Set up Vercel AI Gateway in Pulse

Pulse shows your Vercel team's remaining AI Gateway credit, in US dollars. The gateway has no allowance or period, so there is no ring — only the balance.

## What you need

A Vercel team with AI Gateway, and an AI Gateway API key for that team.

## Steps

1. In the Vercel dashboard, create an AI Gateway API key for the team you want to watch.
2. In Pulse: **Settings → Accounts → Vercel AI Gateway**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the balance appears on the account's card.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste an AI Gateway API key. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Vercel sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Vercel's AI Gateway (`ai-gateway.vercel.sh`) when Pulse checks your balance. To see another team, use that team's key.
