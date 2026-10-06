# Update mirror

Sparkle reads the feed from `raw.githubusercontent.com` and downloads the archive from GitHub's release assets. Both are unreachable or crawl in some places (mainland China most of all), and there an installed Pulse never hears of an update. **update.qunqin.org** is a Cloudflare Worker in front of both: `Scripts/update-mirror/worker.js`.

## What it serves

A proxy and nothing more: no cache and no pages of its own. Two kinds of path, GET and HEAD only; anything else is 404, so it is not an open proxy.

| Path | Passed through to |
|---|---|
| `/appcast.xml`, `/appcast-zh.xml`, `/appcast-en.xml` | the file on `main`, with every `https://github.com/qunqin24/Pulse/releases/download/` rewritten to `https://update.qunqin.org/download/` |
| `/download/v<version>/Pulse-<version>.zip` / `.dmg` | that release asset (GitHub's redirect to its file servers followed); the version in the folder and in the file name must agree |

**The rewrite is the one change it makes, and the feed in the repository keeps GitHub's URLs.** So each route is whole on its own: a Pulse that read the feed from the mirror downloads from the mirror, one that read it from GitHub downloads from GitHub — the fallback below does not depend on Cloudflare. Writing the mirror into the repository's feed instead was considered and not done: GitHub's route would then download through Cloudflare too.

A cache at the edge and a `/download/latest` redirect were written first and taken out: the Worker is meant to stay a proxy, and the download volume does not need one.

**Nothing here can change what Pulse installs.** Sparkle refuses an archive not signed by the EdDSA key in `Info.plist` ([releasing.md](releasing.md#sparkle)), wherever it came from. A broken or hostile mirror can withhold an update, not replace one.

## How the app uses it

**GitHub whenever it answers, the mirror when it does not** (`AppUpdate.FeedRoute`, pinned by `AppUpdateFeedTests`):

- **Asked before the updater starts.** A HEAD for GitHub's `appcast.xml` with a five-second timeout (`AppUpdate.githubReachable`) picks the host, and only then is Sparkle started (`startingUpdater: false`, then `startUpdater()`), so a check due at launch reads the host that answers instead of finding out by failing. A check asked for before the probe is back starts the updater at once.
- **Asked again after every check**, so a Mac that moves between networks follows on its next one.
- **A failed check is tried again straight away on the other host**, not two hours later. Sparkle reports a feed it could not fetch and an archive it could not download as `SUDownloadError` (wrapping the URL error) and a feed that came back as something else — a captive portal's page — as `SUAppcastParseError`; any of those (or a bare `NSURLErrorDomain` / `SUAppcastError`, which Sparkle does not raise today) switches the host and checks again — quietly if the first was About's quiet check, otherwise as a background check, which still puts up the update window when it finds one. **The retry waits for Sparkle's session to clear**, polling for up to three seconds: right after `didFinishUpdateCycleFor` Sparkle schedules the next check, which marks a session in progress until an installer-status probe answers, and a retry asked for in that gap was refused. A session still going after that is a check Sparkle started itself, reading the host just switched to. Once only: when the retry fails too, About says the feed could not be reached and nothing more is tried until the next check. The re-probe after a check is not applied while a check is under way, so it cannot move the host under a check that is reading it. A user's "Check now" shows Sparkle's own error alert before the retry runs.

The feed is chosen per check by `feedURLStringForUpdater:` (`AppUpdate.feedURL(for:host:)`), the host together with Pulse's language ([releasing.md](releasing.md#sparkle) on the per-language feeds). `SUFeedURL` in `Info.plist` stays GitHub's: it is what a build without the delegate would read, and what tells `AppUpdate` it is running from a bundle.

**Copies before 1.8.1 read GitHub only** (their `SUFeedURL` is `raw.githubusercontent.com`). Where GitHub is unreachable they never see the update that moves them to the mirror: those people download the new version once by hand (through the mirror, `https://update.qunqin.org/download/v<version>/Pulse-<version>.dmg`, if GitHub is out of reach).

## Deploying

`qunqin.org` must be a zone on the Cloudflare account. **Not `*.workers.dev`**: that suffix is blocked in mainland China, which is the place this exists for; a custom domain is required.

Dashboard: Workers & Pages → Create → Worker (any starter) named `pulse-update` → Deploy → Edit code → replace everything with `worker.js` → Deploy. Then the Worker's Settings → Domains & Routes → Add → Custom domain → `update.qunqin.org`. Turn off the `workers.dev` route there too.

Or from a terminal, in `Scripts/update-mirror`: `npx wrangler login`, then `npx wrangler deploy` (`wrangler.toml` names the Worker and the custom domain).

Check it:

```bash
curl -s https://update.qunqin.org/appcast.xml | grep -m1 enclosure
curl -sI https://update.qunqin.org/download/v1.8.0/Pulse-1.8.0.dmg
```

The first should print an `update.qunqin.org/download/…` URL, the second `200` with `application/x-apple-diskimage`.

**Changing the Worker** is redeploying `worker.js`; nothing in a release depends on it. Its tests are `node --test Scripts/update-mirror/worker.test.mjs` (a fake GitHub), outside `swift test`.

The free plan's 100,000 requests a day is far above what Pulse's update checks and ~15 MB archives use; with no cache, every download is fetched from GitHub through Cloudflare.
