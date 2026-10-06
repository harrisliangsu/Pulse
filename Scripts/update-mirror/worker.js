// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Pulse's update mirror: a Cloudflare Worker on update.qunqin.org that passes
// requests through to GitHub, for places that cannot reach
// raw.githubusercontent.com or GitHub's release downloads.
// Docs/update-mirror.md says how it is deployed and why.
//
// A proxy and nothing more — no cache, no pages of its own — for two kinds of
// path, so it is not an open proxy:
//
//   /appcast.xml, /appcast-zh.xml, /appcast-en.xml
//       The feed on the repository's main branch. Its one change: every
//       download is pointed at this host, so a copy of Pulse that read the
//       feed here downloads here too, and one that read it from GitHub
//       downloads from GitHub.
//   /download/v1.8.0/Pulse-1.8.0.zip (or .dmg)
//       That release's asset, GitHub's redirect to its file servers followed.
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

export default {
  async fetch(request) {
    return handle(request, fetch);
  },
};

/** The whole worker, with its network passed in so it can be tested. */
export async function handle(request, fetcher) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return plain(405, "Method not allowed", { Allow: "GET, HEAD" });
  }
  const url = new URL(request.url);
  const path = url.pathname;

  if (FEEDS.has(path.slice(1))) {
    const upstream = await fetcher(RAW + path.slice(1));
    if (!upstream.ok) return failed(upstream);
    const body = (await upstream.text()).replaceAll(RELEASES, `${url.origin}/download/`);
    return reply(request, body, { "Content-Type": "application/xml; charset=utf-8" });
  }

  const asset = path.match(ASSET);
  if (asset) {
    const upstream = await fetcher(RELEASES + path.slice("/download/".length), {
      method: request.method,
      redirect: "follow",
    });
    if (!upstream.ok) return failed(upstream);
    const headers = {
      "Content-Type": asset[2] === "zip" ? "application/zip" : "application/x-apple-diskimage",
    };
    const length = upstream.headers.get("Content-Length");
    if (length) headers["Content-Length"] = length;
    return reply(request, upstream.body, headers);
  }

  return plain(404, "Not found");
}

function reply(request, body, headers) {
  return new Response(request.method === "HEAD" ? null : body, { headers });
}

function failed(upstream) {
  return plain(502, `GitHub answered ${upstream.status}`);
}

function plain(status, text, headers = {}) {
  return new Response(text, { status, headers: { "Content-Type": "text/plain; charset=utf-8", ...headers } });
}
