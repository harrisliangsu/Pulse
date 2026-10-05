# Update mirror

Sparkle reads the feed from `raw.githubusercontent.com` and downloads the archive from GitHub's release assets. Both are unreachable or crawl in some places (mainland China most of all), and there an installed Pulse never hears of an update. **update.qunqin.org** is a Cloudflare Worker in front of both: `Scripts/update-mirror/worker.js`.

## What it serves

| Path | From | Edge cache |
|---|---|---|
| `/appcast.xml`, `/appcast-zh.xml`, `/appcast-en.xml` | the file on `main`, with every `https://github.com/qunqin24/Pulse/releases/download/` rewritten to `https://update.qunqin.org/download/` | 5 minutes |
| `/download/v<version>/Pulse-<version>.zip` / `.dmg` | that release asset (GitHub's redirect followed) | a year — an asset never changes |
| `/download/latest` | 302 to the newest version's `.dmg`, read from the feed | — |
| `/` | 302 to the repository | — |

Anything else is 404, and only GET and HEAD are answered: it is not an open proxy. The version in the folder and in the file name must agree. Only a success is cached, keyed by the path without its query, so a GitHub failure is not served for a year and a query string cannot make new copies.

**The feed in the repository keeps GitHub's URLs.** The rewrite happens in the Worker, so each route is whole on its own: a Pulse that read the feed from the mirror downloads from the mirror, one that read it from GitHub downloads from GitHub.

**Nothing here can change what Pulse installs.** Sparkle refuses an archive not signed by the EdDSA key in `Info.plist` ([releasing.md](releasing.md#sparkle)), wherever it came from. A broken or hostile mirror can withhold an update, not replace one.

## How the app uses it

`SUFeedURL` (`Scripts/bundle.sh`) is the mirror, but the feed is chosen per check by `feedURLStringForUpdater:` (`AppUpdate.feedURL(for:host:)`): the host and Pulse's language ([releasing.md](releasing.md#sparkle) on the per-language feeds). **Every launch starts on the mirror.** A check that cannot reach the feed, or cannot download the archive (`NSURLErrorDomain`, `SUAppcastError`, `SUDownloadError`), switches `AppUpdate.host` to the other for the next check — so either host being down costs one check, not every update. Pinned by `AppUpdateFeedTests`.

**Copies before 1.8.1 read GitHub only** (their `SUFeedURL` is `raw.githubusercontent.com`). Where GitHub is unreachable they never see the update that moves them to the mirror: those people download once by hand, from `https://update.qunqin.org/download/latest`, which the Chinese READMEs link.

## Deploying

`qunqin.org` must be a zone on the Cloudflare account. **Not `*.workers.dev`**: that suffix is blocked in mainland China, which is the place this exists for; a custom domain is required.

Dashboard: Workers & Pages → Create → Worker (any starter) named `pulse-update` → Deploy → Edit code → replace everything with `worker.js` → Deploy. Then the Worker's Settings → Domains & Routes → Add → Custom domain → `update.qunqin.org`. Turn off the `workers.dev` route there too.

Or from a terminal, in `Scripts/update-mirror`: `npx wrangler login`, then `npx wrangler deploy` (`wrangler.toml` names the Worker and the custom domain).

Check it:

```bash
curl -s https://update.qunqin.org/appcast.xml | grep -m1 enclosure
curl -sI https://update.qunqin.org/download/latest
```

The first should print an `update.qunqin.org/download/…` URL, the second a 302 to the newest `.dmg`.

**Changing the Worker** is redeploying `worker.js`; nothing in a release depends on it. Its tests are `node --test Scripts/update-mirror/worker.test.mjs` (a fake GitHub and a fake cache), outside `swift test`.

Free plan limits (100,000 requests a day, 512 MB cache objects) are far above what Pulse's update checks and ~15 MB archives use.
