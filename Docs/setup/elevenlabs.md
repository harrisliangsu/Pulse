# Set up ElevenLabs in Blinky

Blinky shows your ElevenLabs subscription's character credits for the current billing period: how much is used, and when it resets.

## What you need

An ElevenLabs account and an API key with the **user_read** permission (the "User" read access in the key's permissions).

## Steps

1. Open [elevenlabs.io/app/settings/api-keys](https://elevenlabs.io/app/settings/api-keys), create a key and give it read access to **User**.
2. In Blinky: **Settings → ElevenLabs**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane shows the credit allowance and when it resets.

## If it doesn't work

| Blinky says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from elevenlabs.io. |
| That key was refused. Check it in Settings. | The key is wrong, revoked, or missing the user_read permission. Edit its permissions or create a new one, then paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | ElevenLabs sent something Blinky doesn't recognize, or the plan reports no character limit. |

## What Blinky reads

Your key is stored encrypted on this Mac and sent only to ElevenLabs' own API (`api.elevenlabs.io`) when Blinky checks your usage. Nothing is generated and no credits are used.
