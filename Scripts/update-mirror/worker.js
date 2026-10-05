// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Pulse's update mirror: a Cloudflare Worker on update.qunqin.org in front of
// GitHub, for places that cannot reach raw.githubusercontent.com or GitHub's
// release downloads. Docs/update-mirror.md says how it is deployed and why.
//
// It serves exactly three things and nothing else, so it is not an open proxy:
//
//   /appcast.xml, /appcast-zh.xml, /appcast-en.xml
//       The feed from the repository's main branch, with every enclosure
//       pointed at this host instead of GitHub, so a copy of Pulse that read
//       the feed here downloads here too. Cached for five minutes.
//   /download/v1.8.0/Pulse-1.8.0.zip (or .dmg)
//       That release's asset, fetched from GitHub once and then kept at the
//       edge: a published asset never changes.
//   /download/latest
//       A redirect to the newest version's .dmg, for a download link that does
//       not go stale.
//
// Nothing here can change what Pulse installs: Sparkle refuses an archive not
// signed by the EdDSA key in the app. The worst a broken mirror can do is be
// unreachable, and the app then reads GitHub on its next check.

const REPO = "qunqin24/Pulse";
const RAW = `https://raw.githubusercontent.com/${REPO}/main/`;
const RELEASES = `https://github.com/${REPO}/releases/download/`;
const FEEDS = new Set(["appcast.xml", "appcast-zh.xml", "appcast-en.xml"]);
// The version in the folder and the file name must agree: v1.8.0/Pulse-1.8.0.zip.
const ASSET = /^\/download\/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\/Pulse-\1\.(zip|dmg)$/;
const FEED_SECONDS = 300;
const ASSET_SECONDS = 31536000;

export default {
  async fetch(request, env, ctx) {
    return handle(request, ctx, fetch, caches.default);
  },
};

/** The whole worker, with its network and cache passed in so it can be tested. */
export async function handle(request, ctx, fetcher, cache) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return plain(405, "Method not allowed", { Allow: "GET, HEAD" });
  }
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === "/") return Response.redirect(`https://github.com/${REPO}`, 302);

  if (FEEDS.has(path.slice(1))) {
    return cached(request, ctx, cache, async () => {
      const upstream = await fetcher(RAW + path.slice(1));
      if (!upstream.ok) return failed(upstream);
      const body = (await upstream.text()).replaceAll(RELEASES, `${url.origin}/download/`);
      return new Response(body, {
        headers: {
          "Content-Type": "application/xml; charset=utf-8",
          "Cache-Control": `public, max-age=${FEED_SECONDS}`,
        },
      });
    });
  }

  if (path === "/download/latest" || path === "/download/latest.dmg") {
    const feed = await handle(new Request(`${url.origin}/appcast.xml`), ctx, fetcher, cache);
    if (!feed.ok) return feed;
    // The feed is newest first.
    const newest = (await feed.text()).match(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/);
    if (!newest) return plain(502, "The feed names no version");
    return Response.redirect(`${url.origin}/download/v${newest[1]}/Pulse-${newest[1]}.dmg`, 302);
  }

  const asset = path.match(ASSET);
  if (asset) {
    return cached(request, ctx, cache, async () => {
      // GitHub answers with a redirect to its file servers; follow it here.
      const upstream = await fetcher(RELEASES + path.slice("/download/".length), { redirect: "follow" });
      if (!upstream.ok) return failed(upstream);
      const headers = new Headers({
        "Content-Type": asset[2] === "zip" ? "application/zip" : "application/x-apple-diskimage",
        "Cache-Control": `public, max-age=${ASSET_SECONDS}, immutable`,
      });
      const length = upstream.headers.get("Content-Length");
      if (length) headers.set("Content-Length", length);
      return new Response(upstream.body, { headers });
    });
  }

  return plain(404, "Not found");
}

/**
 * From the edge cache when it has it, otherwise made and kept. Keyed by the
 * path alone — a query string cannot make a new copy — and only a success is
 * kept, so a GitHub hiccup is not served for the next year.
 */
async function cached(request, ctx, cache, make) {
  const url = new URL(request.url);
  url.search = "";
  const key = new Request(url.toString(), { method: "GET" });
  let response = await cache.match(key);
  if (!response) {
    response = await make();
    if (response.ok) ctx.waitUntil(cache.put(key, response.clone()));
  }
  if (request.method === "HEAD") {
    return new Response(null, { status: response.status, headers: response.headers });
  }
  return response;
}

function failed(upstream) {
  return plain(502, `GitHub answered ${upstream.status}`);
}

function plain(status, text, headers = {}) {
  return new Response(text, { status, headers: { "Content-Type": "text/plain; charset=utf-8", ...headers } });
}
