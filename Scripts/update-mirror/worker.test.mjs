// node --test Scripts/update-mirror/worker.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle } from "./worker.js";

const FEED = `<rss><channel><item>
<sparkle:shortVersionString>1.8.0</sparkle:shortVersionString>
<enclosure url="https://github.com/qunqin24/Pulse/releases/download/v1.8.0/Pulse-1.8.0.zip" />
</item><item>
<sparkle:shortVersionString>1.7.3</sparkle:shortVersionString>
<enclosure url="https://github.com/qunqin24/Pulse/releases/download/v1.7.3/Pulse-1.7.3.zip" />
</item></channel></rss>`;

/** A fake GitHub, a fake edge cache, and a record of what was asked for. */
function world({ status = 200 } = {}) {
  const asked = [];
  const store = new Map();
  const pending = [];
  const fetcher = async (url) => {
    asked.push(url);
    if (status !== 200) return new Response("no", { status });
    if (url.endsWith(".xml")) return new Response(FEED);
    return new Response("archive-bytes", { headers: { "Content-Length": "13" } });
  };
  const cache = {
    match: async (request) => store.get(request.url)?.clone(),
    put: async (request, response) => { store.set(request.url, response); },
  };
  const ctx = { waitUntil: (promise) => pending.push(promise) };
  const get = async (path, method = "GET") => {
    const response = await handle(new Request(`https://update.qunqin.org${path}`, { method }), ctx, fetcher, cache);
    await Promise.all(pending.splice(0));
    return response;
  };
  return { asked, get };
}

test("the feed comes from main with its downloads pointed here", async () => {
  const { asked, get } = world();
  const response = await get("/appcast.xml");
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.equal(asked[0], "https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml");
  assert.match(body, /https:\/\/update\.qunqin\.org\/download\/v1\.8\.0\/Pulse-1\.8\.0\.zip/);
  assert.doesNotMatch(body, /github\.com\/qunqin24\/Pulse\/releases/);
});

test("the one-language feeds are served too", async () => {
  const { asked, get } = world();
  assert.equal((await get("/appcast-zh.xml")).status, 200);
  assert.equal((await get("/appcast-en.xml")).status, 200);
  assert.deepEqual(asked.map((url) => url.split("/").pop()), ["appcast-zh.xml", "appcast-en.xml"]);
});

test("an asset is fetched from the release once, then from the cache", async () => {
  const { asked, get } = world();
  const first = await get("/download/v1.8.0/Pulse-1.8.0.zip");
  assert.equal(first.status, 200);
  assert.equal(await first.text(), "archive-bytes");
  assert.equal(first.headers.get("Content-Type"), "application/zip");
  assert.equal(asked[0], "https://github.com/qunqin24/Pulse/releases/download/v1.8.0/Pulse-1.8.0.zip");
  const again = await get("/download/v1.8.0/Pulse-1.8.0.zip?bust=1");
  assert.equal(await again.text(), "archive-bytes");
  assert.equal(asked.length, 1);
});

test("only Pulse's own release files are proxied", async () => {
  const { asked, get } = world();
  for (const path of [
    "/download/v1.8.0/Pulse-1.7.3.zip",
    "/download/v1.8.0/Other-1.8.0.zip",
    "/download/v1.8.0/Pulse-1.8.0.exe",
    "/download/../../evil",
    "/https://example.com/",
    "/appcast.xml.bak",
  ]) {
    assert.equal((await get(path)).status, 404, path);
  }
  assert.equal(asked.length, 0);
});

test("latest redirects to the newest dmg in the feed", async () => {
  const { get } = world();
  const response = await get("/download/latest");
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("Location"), "https://update.qunqin.org/download/v1.8.0/Pulse-1.8.0.dmg");
});

test("HEAD answers without a body and other methods are refused", async () => {
  const { get } = world();
  const head = await get("/download/v1.8.0/Pulse-1.8.0.dmg", "HEAD");
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  assert.equal((await get("/appcast.xml", "POST")).status, 405);
});

test("a GitHub failure is passed on as 502 and not cached", async () => {
  const { asked, get } = world({ status: 503 });
  assert.equal((await get("/appcast.xml")).status, 502);
  assert.equal((await get("/appcast.xml")).status, 502);
  assert.equal(asked.length, 2);
});
