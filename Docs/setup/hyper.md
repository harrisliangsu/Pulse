# Set up Hyper in Pulse

Pulse shows your Charm Hyper Hypercredit balance. Hyper reports a balance only — no allowance and no period — so there is no ring, just the balance on the account's pane.

## What you need

A Charm Hyper account and an API key.

## Steps

1. Sign in at [hyper.charm.land](https://hyper.charm.land) and create an API key.
2. In Pulse: **Settings → Accounts → Hyper**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the balance appears on the account's pane, in HC (Hypercredits).

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from hyper.charm.land. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Hyper sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Hyper's own API (`hyper.charm.land`) when Pulse checks your balance.
