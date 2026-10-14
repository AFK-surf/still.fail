import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { FRAME_CSP, pageCsp, shareFiles } from "../src/share.ts";

// Published chats (docs/public-share.md): the relays, for anyone, which the share page reaches the station through; the
// share host, a static site of its own whose headers keep its page to its own scripts, the cloud and the relays.

test("the relays are told to anyone, from any page, as the stations are told them", async () => {
  const h = await harness({ relayUrl: "https://relay.one.example" });
  try {
    const answer = await h.fetch("/v1/relays", { headers: { origin: "https://share.still.fail" } });
    assert.equal(answer.status, 200);
    assert.equal(answer.headers.get("access-control-allow-origin"), "*");
    assert.deepEqual(await answer.json(), { relay_urls: ["https://relay.one.example"] });
    // Not signed in, and not a secret on the test channel's host either.
    assert.equal((await h.fetchBeta("/v1/relays")).status, 200);
    // Only read.
    assert.equal((await h.fetch("/v1/relays", { method: "POST" })).status, 404);
  } finally {
    await h.close();
  }
});

test("the share host serves its page and its frame, each with its policy, and nothing else", async () => {
  const h = await harness();
  try {
    const page = await h.fetchShare("/");
    assert.equal(page.status, 200);
    assert.equal(await page.text(), "<title>still.fail 分享</title>");
    assert.equal(page.headers.get("x-robots-tag"), "noindex, nofollow");
    assert.equal(page.headers.get("referrer-policy"), "no-referrer");
    const csp = page.headers.get("content-security-policy") ?? "";
    assert.match(csp, /script-src 'self' 'wasm-unsafe-eval';/);
    assert.match(csp, /connect-src 'self' https:\/\/relay\.example wss:\/\/relay\.example https:\/\/39\.105\.157\.122 wss:\/\/39\.105\.157\.122;/);
    assert.match(csp, /frame-ancestors 'none'/);
    assert.equal((await h.fetchShare("/", { method: "HEAD" })).headers.get("content-security-policy"), csp);
    const frame = await h.fetchShare("/frame");
    assert.equal(frame.status, 200);
    assert.match(await frame.text(), /document\.write/);
    assert.equal(frame.headers.get("content-security-policy"), FRAME_CSP, "the frames' own, not the page's");
    assert.equal(frame.headers.get("x-robots-tag"), "noindex, nofollow");
    // Its files have the headers all of it has, and no policy of a page.
    const script = await h.fetchShare("/assets/share.js");
    assert.equal(script.status, 200);
    assert.equal(script.headers.get("content-security-policy"), null);
    assert.equal(script.headers.get("x-content-type-options"), "nosniff");
    for (const path of ["/_headers", "/anything", "/w/x/chats"]) assert.equal((await h.fetchShare(path)).status, 404, path);
    assert.equal((await h.fetchShare("/", { method: "POST" })).status, 405);
  } finally {
    await h.close();
  }
});

test("the page talks to the cloud and the relays it was built for, a dev cloud's over plain HTTP too", () => {
  const csp = pageCsp({ cloud: "http://127.0.0.1:8877", relays: ["http://127.0.0.1:3340", "https://cn.example/relay"] });
  assert.match(csp, /connect-src 'self' http:\/\/127\.0\.0\.1:8877 http:\/\/127\.0\.0\.1:3340 ws:\/\/127\.0\.0\.1:3340 https:\/\/cn\.example wss:\/\/cn\.example;/);
  // Images it read from the station are blob: URLs; frames come only from its own /frame.
  assert.match(csp, /img-src 'self' blob: data:;/);
  // The file preview's video and audio play from blob: URLs too; nothing runs from one.
  assert.match(csp, /media-src blob:;/);
  assert.doesNotMatch(csp, /script-src[^;]*blob:/);
  assert.match(csp, /frame-src 'self';/);
  assert.doesNotMatch(csp, /script-src[^;]*unsafe-inline/);
  // The frame writes in only what its parent posts, once.
  assert.match(shareFiles({ cloud: "https://app.still.fail", relays: [] })["frame.html"]!, /event\.source !== parent/);
});
