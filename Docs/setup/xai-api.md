# Set up xAI API in Pulse

Pulse shows the prepaid credit left on an xAI developer-platform team. This is the API platform at console.x.ai, not a Grok or SuperGrok subscription; for those, set up **Grok** instead.

## What you need

A team on [console.x.ai](https://console.x.ai) with prepaid credit, and permission to create a management key.

## Steps

1. In the xAI Console, open **Settings → Management Keys** and create a key. An ordinary API key (the kind used to call models) won't work.
2. Find your **team ID**: it's in the console's address bar and in the team settings.
3. In Pulse: **Settings → Accounts → xAI API**. Turn on **Show in panel**. Under **Connection**, enter the team ID, a colon, then the key — `TeamID:ManagementKey` — into **API key**, and click **Save**.
4. Within a few seconds the balance appears on the account's card. There is no ring: prepaid credit isn't a limit.

The balance is xAI's **posted** figure, which xAI updates when a billing cycle closes. Partway through a cycle it can read higher than the console's live remainder.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Enter `TeamID:ManagementKey`. |
| That key was refused. Check it in Settings. | Check the format (team ID, colon, key), that the key is a management key, and that it belongs to that team. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem, or a team ID xAI doesn't know. Check the team ID, then try again. |
| Couldn't read the reply. | xAI sent something Pulse doesn't recognize. Try again later. |

## What Pulse reads

The team ID and key are stored encrypted on this Mac and sent only to `management-api.x.ai` when Pulse checks the balance.
