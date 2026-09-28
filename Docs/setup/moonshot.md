# Set up Moonshot in Pulse

Pulse shows the money left on your Moonshot (Kimi Open Platform) API account: in US dollars on the international platform, in yuan on the China platform. The platform reports a balance and no allowance, so there is no ring to fill — the balance is the reading.

This is the pay-as-you-go API. The Kimi Code subscription is a separate provider in Pulse.

## What you need

An API key from the Kimi Open Platform — the international console ([platform.moonshot.ai](https://platform.moonshot.ai)) or the China one. Either works; you don't pick which.

## Steps

1. Sign in to the platform's console and create an API key.
2. In Pulse: **Settings → Accounts → Moonshot**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the account shows its balance.

Pulse asks the international platform first. If it refuses the key, Pulse asks the China platform, and remembers which one accepted it until Pulse quits.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from the platform's console. |
| That key was refused. Check it in Settings. | Neither platform accepted it. Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Moonshot sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Moonshot's own API (`api.moonshot.ai`, and `api.moonshot.cn` if the first refuses it) when Pulse checks your balance.
