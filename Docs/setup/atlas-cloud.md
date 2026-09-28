# Set up Atlas Cloud in Pulse

Pulse shows your Atlas Cloud account's available balance. It's a balance, not an allowance, so there is no ring — the balance appears on the account's pane, and you can have Pulse warn you when it runs low.

## What you need

An Atlas Cloud API key that is allowed to read the account balance: the account owner's key, or for a team a key with the Account Admin or Finance role. A public key ID (`ak_…`) won't work.

## Steps

1. Sign in at [atlascloud.ai](https://www.atlascloud.ai) and create an API key with balance access.
2. In Pulse: **Settings → Accounts → Atlas Cloud**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the balance appears on the account's pane.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from atlascloud.ai. |
| That key was refused. Check it in Settings. | The key is wrong, revoked, or can't read the balance. Use the owner's key or an Account Admin/Finance key. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Atlas Cloud sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Atlas Cloud's own API (`api.atlascloud.ai`) when Pulse checks your balance. Coding Plan quotas aren't read.
