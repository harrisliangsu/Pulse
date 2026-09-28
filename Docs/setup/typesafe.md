# Set up TypeSafe in Pulse

Pulse shows the credit balance on your TypeSafe console's billing page. TypeSafe reports no allowance or percentage, so there is no ring to fill — the balance is the reading.

## What you need

A TypeSafe account, signed in at [console.typesafe.ai](https://console.typesafe.ai) in a browser. An inference API key can't read billing.

**Read from browser doesn't work for TypeSafe yet.** Pulse only keeps cookies it can name, and the name of the console's session cookie isn't known. You copy the whole Cookie header from your browser instead, once.

## Steps

1. In your browser, open [console.typesafe.ai/settings/billing](https://console.typesafe.ai/settings/billing) while signed in.
2. Open the browser's developer tools (Safari: **Develop → Show Web Inspector**; Chrome: **View → Developer → Developer Tools**), go to **Network**, and reload the page.
3. Click the first request, `billing`. Under its request headers, copy the value of **Cookie** — the long line of `name=value; name=value`.
4. In Pulse: **Settings → Accounts → TypeSafe**. Turn on **Show in panel**. Under **Connection**, paste it into **Session cookie** and click **Save**.
5. Within a few seconds the account shows its balance.

When the console signs you out, the copied header stops working; repeat steps 1–4.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Read a browser session in Settings. | Paste the Cookie header (steps 1–4). |
| No session found. Sign in at console.typesafe.ai first. | Read from browser can't find TypeSafe's session. Paste the header instead (steps 1–4). |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in to the console again and paste a fresh Cookie header. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | TypeSafe changed its billing page, and Pulse doesn't recognize it. |

## What Pulse reads

The header you paste is stored encrypted on this Mac and sent only to TypeSafe's console (`console.typesafe.ai`) when Pulse checks your balance. To find the page's billing call, Pulse also opens the console's own public scripts, without your cookies.
