# Set up Alibaba Coding Plan in Pulse

Pulse shows your Alibaba Cloud Coding Plan's three allowances: the 5-hour window, the weekly window and the monthly allowance, each as the amount used out of the amount your plan grants.

## What you need

A Coding Plan subscription in Alibaba Cloud Model Studio (百炼), on either the international site or the China mainland site, and the API key that comes with it.

## Steps

1. Open the Coding Plan page in Model Studio — [international](https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan) or [China mainland](https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan) — and copy the plan's API key.
2. In Pulse: **Settings → Accounts → Alibaba Coding Plan**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists the allowances and when each resets.

There is no site to choose. Pulse asks the international console first and the China mainland console second, and reads whichever one knows your key.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste the key from the Coding Plan page. |
| That key was refused. Check it in Settings. | Copy the key again from the Coding Plan page. Some accounts' consoles only answer a signed-in browser, not a key — Pulse cannot read those accounts with a key yet. |
| This account has no plan with usage limits. | The console lists no Coding Plan on this account, or only an expired one. |
| No limits reported. | The console answered but gave no allowance with both an amount used and a total. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | The console sent something Pulse doesn't recognize. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Alibaba Cloud's own consoles (`modelstudio.console.alibabacloud.com`, then `bailian.console.aliyun.com` if the first doesn't know it) when Pulse checks your usage.
