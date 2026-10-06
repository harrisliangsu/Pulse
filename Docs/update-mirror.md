# Update mirror

**This fork does not use it.** Installed copies of harrisliangsu/Pulse read `https://raw.githubusercontent.com/harrisliangsu/Pulse/main/appcast.xml` (and `appcast-zh.xml` / `appcast-en.xml` when a language is set). They do not read qunqin24/Pulse, and they do not fall back to **update.qunqin.org**. `AppUpdate.feedBase(from:)` ignores a plist URL that is not this fork's GitHub feed. The worker under `Scripts/update-mirror/` is upstream's, kept so the file is not dropped on the next sync; nothing in this repository's app or release workflow calls it.

Upstream uses the mirror because GitHub is unreachable in some places. The rest of this page describes that worker, not a host this fork's app will contact.

## What it serves

A proxy and nothing more: no cache and no pages of its own. Two kinds of path, GET and HEAD only; anything else is 404, so it is not an open proxy.

| Path | Passed through to |
|---|---|
| `/appcast.xml`, `/appcast-zh.xml`, `/appcast-en.xml` | the file on `main`, with every `https://github.com/qunqin24/Pulse/releases/download/` rewritten to `https://update.qunqin.org/download/` |
| `/download/v<version>/Pulse-<version>.zip` / `.dmg` | that release asset (GitHub's redirect to its file servers followed); the version in the folder and in the file name must agree |

**The rewrite is the one change it makes, and the feed in the repository keeps GitHub's URLs.** So each route is whole on its own: a Pulse that read the feed from the mirror downloads from the mirror, one that read it from GitHub downloads from GitHub — the fallback below does not depend on Cloudflare. Writing the mirror into the repository's feed instead was considered and not done: GitHub's route would then download through Cloudflare too.

A cache at the edge and a `/download/latest` redirect were written first and taken out: the Worker is meant to stay a proxy, and the download volume does not need one.

**Nothing here can change what Pulse installs.** Sparkle refuses an archive not signed by the EdDSA key in `Info.plist` ([releasing.md](releasing.md#sparkle)), wherever it came from. A broken or hostile mirror can withhold an update, not replace one.

## How this fork's app chooses a feed

One host. `feedURLStringForUpdater:` calls `AppUpdate.feedURL(for:base:)` (`AppUpdateFeedTests`):

- Following the system reads `appcast.xml`. Simplified and Traditional Chinese read `appcast-zh.xml`. English, Japanese and Korean read `appcast-en.xml`.
- The directory is `https://raw.githubusercontent.com/harrisliangsu/Pulse/main/`. A `SUFeedURL` that already names that path may supply the directory; `update.qunqin.org` and `qunqin24/Pulse` do not.
- A check that fails is reported. It is not tried again on another host.

`SUFeedURL` in `Info.plist` stays this fork's GitHub URL: it is what a build without the delegate would read, and what tells `AppUpdate` it is running from a bundle. [releasing.md](releasing.md#sparkle)

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
