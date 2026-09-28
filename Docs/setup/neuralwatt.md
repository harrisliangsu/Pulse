# Set up Neuralwatt in Pulse

Pulse shows your Neuralwatt subscription's kWh allowance for the current period, the key's own spending allowance if you set one, and your prepaid credit balance in US dollars.

## What you need

A Neuralwatt account with an API key. The subscription and the spending allowance are optional; without them Pulse shows the balance alone.

## Steps

1. Open [portal.neuralwatt.com](https://portal.neuralwatt.com/dashboard) and create or copy an API key.
2. In Pulse: **Settings → Accounts → Neuralwatt**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears (or the balance, with no subscription). The pane lists the monthly limit with its period end, and the key's spend limit.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from portal.neuralwatt.com. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Neuralwatt sent something Pulse doesn't recognize, or reported no balance and no allowance. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Neuralwatt's own service (`api.neuralwatt.com`) when Pulse checks your usage.
