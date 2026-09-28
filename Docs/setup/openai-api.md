# Set up OpenAI API in Pulse

Pulse shows the prepaid credit left on your OpenAI API account, as a dollar balance. There is no ring: the API has no allowance for a percentage to be of.

## What you need

An OpenAI API account with prepaid credit, and an API key that can read the account's billing. Older user keys can; OpenAI's newer project and service-account keys usually cannot (see below).

## Steps

1. Sign in at [platform.openai.com](https://platform.openai.com) and create an API key under **API keys**.
2. In Pulse: **Settings → Accounts → OpenAI API**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the account's card shows the balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from platform.openai.com. |
| That key was refused. Check it in Settings. | OpenAI turned the key away for both the balance and the organization's usage. Check it is active; a project key may not read either. |
| No limits reported. | The key works — it is an Admin key, or a key that can read the organization's usage — but OpenAI doesn't give it the balance. Pulse can't show spend totals yet, so there is nothing to show for it. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | OpenAI sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to OpenAI's own service (`api.openai.com`) when Pulse checks the balance. Pulse asks for the balance and, only if that is refused, for one day of the organization's costs to learn whether the key itself works; it never makes a model request.
