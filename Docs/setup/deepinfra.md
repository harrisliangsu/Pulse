# Set up DeepInfra in Pulse

Pulse shows your DeepInfra prepaid balance in US dollars. If you have set a spending limit on the account, it also shows this billing cycle's spend against it as a ring.

## What you need

A DeepInfra account and an API key.

## Steps

1. Open the [DeepInfra dashboard](https://deepinfra.com/dash) and create an API key.
2. In Pulse: **Settings → Accounts → DeepInfra**. Turn on **Show in panel**. Under **Connection**, paste the key (without a `Bearer ` prefix) into **API key** and click **Save**.
3. Within a few seconds the balance appears — and the ring, if you have a spending limit.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from deepinfra.com. |
| That key was refused. Check it in Settings. | The key is wrong, or can't read billing data. Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | DeepInfra sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to DeepInfra's own API (`api.deepinfra.com`) when Pulse checks your balance.
