# Set up New API in Pulse

[New API](https://github.com/QuantumNous/new-api) is the gateway most self-run AI relays are built on. Pulse shows your remaining balance on the deployment as money — the same key you already use for that relay in your coding tool is all it needs. New API doesn't reliably say what a percentage there would mean, so Pulse never draws one for it — only the balance.

## What you need

Access to a running New API deployment (its web address) and an `sk-` API key issued on it — the same key already in your AI client's configuration for this relay, if you have one.

## Steps

1. Get your key: if you already use this relay in a coding tool, its `sk-` key works here too — copy it from that tool's config. Otherwise, sign in to the deployment's web console (the address your operator gave you), open the **Tokens** page, and create a new one (usually a "Generate" or "Add Token" button).
   <!-- unverified: exact wording confirmed from New API's own English UI strings (web/src/i18n/locales/en.json: "Tokens", "Create API token", "Click \"Generate\" to create a token"), but not checked against a live running console, and operators can customize branding. -->
2. In Pulse, go to Settings → Accounts → New API and turn on "Show in panel". Fill in "Server address" with your deployment's address — the same base URL your client uses, such as `https://gateway.example.com` — and click Save; Pulse assumes `https://` if you don't type a scheme, and only accepts plain `http://` for an address on your own network, such as `localhost`. Then paste your `sk-` key into "API key" and click Save.
3. Success looks like a balance shown for New API on the Pulse panel. If your deployment reports its currency as a token count or a custom unit rather than a real currency, Pulse shows nothing rather than guessing — this is expected, not a failure.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Add the server address in Settings. | Fill in "Server address" with your deployment's URL. |
| That address can't be used. It needs https://, unless the server is on your own network. | Use an `https://` address, or `http://` only if the server is on your own machine or local network. |
| Add an API key in Settings. | Paste your `sk-` key into "API key". |
| That key was refused. Check it in Settings. | The key is wrong, revoked, or for a different deployment. Get a fresh one from the console's Tokens page. |

## What Pulse reads

Pulse sends your `sk-` key to `{your address}/v1/dashboard/billing/subscription` and `/v1/dashboard/billing/usage` on the deployment you typed (the same billing routes New API implements for OpenAI-client compatibility), plus a public, keyless status route that says what currency the deployment reports in. Nothing else is sent, and no model request is ever made through it. The address and key are kept encrypted on this Mac (`keys.dat`).
