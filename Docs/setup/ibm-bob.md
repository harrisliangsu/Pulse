# Set up IBM Bob in Pulse

Pulse shows the Bobcoins used this month against your team's budget, as a ring with the refresh date IBM Bob reports. If your key sees several teams, the ring is their total — shown only when every team has a budget.

## What you need

An IBM Bob subscription, and an API key from the IBM Bob web portal.

## Steps

1. Sign in at [bob.ibm.com](https://bob.ibm.com) and create an API key.
2. In Pulse: **Settings → Accounts → IBM Bob**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, with your plan's name on the card.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from bob.ibm.com. |
| That key was refused. Check it in Settings. | Check the key is active and can read subscription usage; create a fresh one if not. |
| This account has no plan with usage limits. | The key sees no IBM Bob subscription or team. |
| No limits reported. | At least one of your teams has no Bobcoin budget (it is unlimited), so there is no total to draw a ring against. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | IBM Bob sent something Pulse doesn't recognize, or named a server outside `bob.ibm.com`, which Pulse won't send your key to. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to IBM Bob's own servers (`bob.ibm.com` and its regional hosts, such as `api.us-east.bob.ibm.com`) when Pulse checks your usage.
