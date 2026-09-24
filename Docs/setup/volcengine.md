# Set up Volcengine in Pulse

Pulse shows usage for Volcengine's Ark Coding Plan (the coding-agent plan sold on Volcengine's Ark platform) — its 5-hour, weekly, and monthly windows, whichever your plan reports.

## What you need

An Ark Coding Plan (or Agent Plan) on Volcengine (火山引擎), and either the `arkcli` command-line tool signed in, or an access key pair from the Volcengine console.

## Steps

Turn on the provider first: go to Settings → Accounts → Volcengine and turn on "Show in panel". Then connect it one of two ways — Pulse tries your pasted access keys first if you've entered them, and falls back to `arkcli`'s saved login otherwise.

**Option A — arkcli (no pasting required)**
1. Install: `npm install -g @volcengine/ark-cli@latest`. Check it worked with `arkcli --version`.
2. Sign in: `arkcli auth login` (Volcengine SSO is the recommended option). When asked, choose the Coding Plan consumption type.
3. Back in Settings → Accounts → Volcengine, leave "Read usage from" on "Automatic" (or choose "Provider tooling" to use arkcli only). Refresh Pulse and a ring for Volcengine fills in.

**Option B — a pasted access key pair**
1. Log in to the [Volcengine console](https://console.volcengine.com/iam/keymanage/), go to IAM → Access Keys, and click "Create Key". Confirm the security prompt, then download or copy the AccessKeyId and SecretAccessKey shown.
2. In Settings → Accounts → Volcengine, in the "Access keys" field, type them as `AccessKeyID:SecretAccessKey` (one colon between the two, no spaces), then click "Save".
3. Pulse now prefers this pasted key pair over `arkcli`'s login, even with both present — this is deliberate, so it reports on the account you typed the keys for rather than whichever one arkcli happens to be signed in to. "Read usage from" can stay on "Automatic".

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Install arkcli and run `arkcli auth login`, or add access keys in Settings. | Follow Option A or Option B above. |
| arkcli isn't signed in. Run `arkcli auth login`. | Run that command in Terminal, then retry. |
| Add an API key in Settings. | Paste your access key pair (see Option B). |
| That key was refused. Check it in Settings. | Re-check the pair — a common mistake is swapping the Access Key ID and Secret, or missing the colon between them. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/Pulse/issues). |
| No limits reported. | Your account may not have a running Coding Plan or Agent Plan. |

## What Pulse reads

A pasted access key pair is stored encrypted on this Mac and used only to sign requests to Volcengine's usage API. If you use `arkcli` instead, Pulse runs it and reads its own saved login — nothing from that login is copied into Pulse.
