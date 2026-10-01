import { test } from "node:test";
import assert from "node:assert/strict";
import { PreviewCache } from "../web/src/previewCache.ts";
import { bridge, type Asked, type Answer } from "../web/src/previewBridge.ts";

const asked = (extra: Partial<Asked> = {}): Asked => ({ id: 1, method: "GET", path: "/module.js?v=1", headers: [], body: null, ...extra });
const answer = (extra: Partial<Answer> = {}): Answer => ({ status: 200, headers: [["content-type", "text/javascript"], ["cache-control", "max-age=3600"], ["etag", '"v1"']], body: new TextEncoder().encode("export default 1"), ...extra });

test("fresh static resources are reused without detaching cached bytes; keys include path and request headers", () => {
  const cache = new PreviewCache();
  cache.prepare(asked()).save(answer());
  const first = cache.prepare(asked()).fresh!;
  structuredClone(first.body, { transfer: [first.body.buffer] });
  assert.equal(first.body.length, 0);
  assert.equal(new TextDecoder().decode(cache.prepare(asked()).fresh!.body), "export default 1");
  assert.equal(cache.prepare(asked({ path: "/module.js?v=2" })).fresh, undefined);
  assert.equal(cache.prepare(asked({ headers: [["accept", "text/css"]] })).fresh, undefined);
  assert.equal(new PreviewCache().prepare(asked()).fresh, undefined);
});

test("no-cache resources revalidate with ETag, and 304 restores the body and updates response policy", () => {
  const cache = new PreviewCache();
  cache.prepare(asked()).save(answer({ headers: [["content-type", "text/javascript"], ["cache-control", "no-cache"], ["etag", '"v1"']] }));
  const pending = cache.prepare(asked());
  assert.equal(pending.fresh, undefined);
  assert.equal(new Headers(pending.headers).get("if-none-match"), '"v1"');
  const restored = pending.revalidated({ status: 304, headers: [["cache-control", "max-age=600"]] })!;
  assert.equal(restored.status, 200);
  assert.deepEqual(restored.body, answer().body);
  pending.save(restored);
  assert.ok(cache.prepare(asked()).fresh);
});

test("reload re-fetches, no-store and explicit conditionals/ranges bypass, old upstream ages are respected", () => {
  const cache = new PreviewCache();
  cache.prepare(asked()).save(answer());
  for (const request of [asked({ cache: "reload" }), asked({ cache: "no-store" }), asked({ headers: [["range", "bytes=0-3"]] }), asked({ headers: [["cookie", "session=a"]] })]) {
    const pending = cache.prepare(request);
    assert.equal(pending.fresh, undefined);
    assert.equal(new Headers(pending.headers).has("if-none-match"), false);
  }
  const explicit = cache.prepare(asked({ headers: [["if-none-match", '"custom"']] }));
  assert.equal(explicit.revalidated({ status: 304, headers: [] }), undefined);
  cache.prepare(asked()).save(answer({ headers: [...answer().headers, ["age", "3601"]] }));
  assert.equal(cache.prepare(asked()).fresh, undefined);
});

test("dynamic, no-store, wildcard Vary, cookies, and oversized answers are not cached", () => {
  for (const response of [
    answer({ headers: [["content-type", "application/json"], ["cache-control", "max-age=600"]] }),
    answer({ headers: [...answer().headers.filter(([k]) => k !== "cache-control"), ["cache-control", "no-store"]] }),
    answer({ headers: [...answer().headers, ["vary", "*"]] }),
    answer({ headers: [...answer().headers, ["set-cookie", "session=a"]] }),
    answer({ body: new Uint8Array(4 * 1024 * 1024 + 1) }),
  ]) {
    const cache = new PreviewCache(); cache.prepare(asked()).save(response);
    assert.equal(cache.prepare(asked()).fresh, undefined);
    assert.equal(new Headers(cache.prepare(asked()).headers).has("if-none-match"), false);
  }
});

test("mutations clear cached resources and prevent older in-flight requests from repopulating them", () => {
  const cache = new PreviewCache();
  const pending = cache.prepare(asked()); pending.save(answer());
  cache.prepare(asked({ method: "POST", path: "/update" }));
  pending.save(answer());
  assert.equal(cache.prepare(asked()).fresh, undefined);
});

test("entry and byte budgets evict resources", () => {
  const cache = new PreviewCache();
  for (let i = 0; i < 257; i++) cache.prepare(asked({ path: `/${i}.js` })).save(answer());
  assert.equal(cache.prepare(asked({ path: "/0.js" })).fresh, undefined);
  cache.clear();
  for (let i = 0; i < 9; i++) cache.prepare(asked({ path: `/${i}.js` })).save(answer({ body: new Uint8Array(4 * 1024 * 1024) }));
  assert.equal(cache.prepare(asked({ path: "/0.js" })).fresh, undefined);
  assert.ok(cache.prepare(asked({ path: "/8.js" })).fresh);
});

test("the real message bridge streams once, reuses immutable bytes, revalidates source, and fetches changed source", async () => {
  const { port1, port2 } = new MessageChannel();
  let calls = 0, version = 1;
  const stop = bridge(port1, { station: "s", service: 1234, streams: true, call: async (_name, params, progress) => {
    calls++;
    const p = params as { path: string; headers: [string, string][] };
    const etag = `"${version}"`;
    const unchanged = new Headers(p.headers).get("if-none-match") === etag;
    progress!({ head: { status: unchanged ? 304 : 200, headers: [["content-type", "text/javascript"], ["cache-control", p.path === "/dep.js" ? "max-age=3600, immutable" : "no-cache"], ["etag", etag]] } });
    if (!unchanged) progress!({ chunk: btoa(`export default ${version}`) });
    return {};
  } });
  const get = (id: number, path: string) => new Promise<{ status: number; body: string }>((resolve, reject) => {
    let status = 0, body = "";
    port2.onmessage = ({ data }) => {
      if (data.error) reject(new Error(data.error));
      if (data.head) status = data.head.status;
      if (data.chunk) body += new TextDecoder().decode(data.chunk);
      if (data.end) resolve({ status, body });
    };
    port2.postMessage(asked({ id, path }));
  });
  try {
    assert.deepEqual(await get(1, "/dep.js"), { status: 200, body: "export default 1" });
    assert.deepEqual(await get(2, "/dep.js"), { status: 200, body: "export default 1" });
    assert.equal(calls, 1);
    await get(3, "/src.js");
    assert.deepEqual(await get(4, "/src.js"), { status: 200, body: "export default 1" });
    assert.equal(calls, 3);
    version++;
    assert.deepEqual(await get(5, "/src.js"), { status: 200, body: "export default 2" });
  } finally { stop(); port2.close(); }
});
