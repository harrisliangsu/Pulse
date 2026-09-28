# Set up Venice in Pulse

Pulse shows the balance your Venice API key spends from — US dollars, or DIEM if your account spends DIEM. Venice reports a balance and no allowance, so there is no ring to fill — the balance is the reading.

## What you need

A Venice API key, from the API section of your settings at [venice.ai](https://venice.ai).

## Steps

1. Sign in at venice.ai and create an API key.
2. In Pulse: **Settings → Accounts → Venice**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the account shows its balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from venice.ai. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Venice sent something Pulse doesn't recognize. |
| No limits reported. | Venice reported neither a dollar nor a DIEM balance. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Venice's own API (`api.venice.ai`) when Pulse checks your balance. Pulse doesn't show subscription credits from the Venice website.
