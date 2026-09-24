# Set up z.ai / Zhipu (GLM Coding Plan) in Pulse

z.ai and Zhipu (BigModel) are one company's two storefronts — international and mainland — for the same GLM Coding Plan. They are **separate accounts with separate keys**: a z.ai key is refused on Zhipu, and a Zhipu key is refused on z.ai. Pulse gives each its own row, named **z.ai** and **Zhipu**, so pick the one that matches where you actually subscribed.

For either one, Pulse shows your Coding Plan's limit windows (for example a 5-hour and a weekly limit).

## z.ai

### What you need
A GLM Coding Plan subscription bought through z.ai (see [z.ai/subscribe](https://z.ai/subscribe)).

### Steps
1. Open [z.ai/manage-apikey/apikey-list](https://z.ai/manage-apikey/apikey-list), sign in, and click **+ Create a new API key**. Copy it.
2. In Pulse: **Settings → Accounts → z.ai**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the z.ai ring appears with your plan's windows.

## Zhipu (GLM Coding Plan, mainland)

### What you need
A GLM Coding Plan subscription bought through BigModel/Zhipu (see [open.bigmodel.cn/glm-coding](https://open.bigmodel.cn/glm-coding)).

### Steps
1. Open [open.bigmodel.cn](https://open.bigmodel.cn), sign in, and subscribe to (or confirm) your Coding Plan. Find your API key under your account's key management page (sometimes labelled "我的密钥" / My Plans → API Keys). Copy it. <!-- unverified: exact click path/labels on open.bigmodel.cn's key page — the site is a JS app that couldn't be scraped for exact menu text; based on third-party guides rather than a directly fetched page -->
2. In Pulse: **Settings → Accounts → Zhipu**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
   - If you've already saved a GLM key to disk with another coding tool — at `~/.coding-relay/glm-api-key`, `~/.config/bigmodel/api_key`, or `~/.config/zhipu/api_key` — Pulse finds it automatically and there's nothing to paste. This fallback is **mainland-only**; it's never used for the z.ai row.
3. Within a few seconds the Zhipu ring appears with your plan's windows.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from the matching console above (nothing was found either pasted or on disk). |
| That key was refused. Check it in Settings. | Often means the key is from the *other* storefront — double-check you pasted a z.ai key into z.ai, and a Zhipu key into Zhipu. Otherwise the key itself may be wrong or expired. |
| That key works. The account has no Coding Plan running on it. | The key is valid, but this account's Coding Plan subscription has lapsed or was never bought. Subscribe or renew, then retry. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | The provider sent something Pulse doesn't recognize yet. Try again later. |

## What Pulse reads

Each key is stored encrypted on this Mac and sent only to the matching company's own server — a z.ai key only ever goes to z.ai, a Zhipu key only ever goes to open.bigmodel.cn. For Zhipu, if no key is pasted, Pulse may instead read one of the local key files listed above.
