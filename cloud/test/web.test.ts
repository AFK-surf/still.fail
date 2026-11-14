import assert from "node:assert/strict";
import test from "node:test";
import { brotliCompressSync, brotliDecompressSync } from "node:zlib";
import { serveWeb } from "../src/web.ts";

// src/web.ts `packed`, read as it answers (test/hosts.test.ts has it in Miniflare, which keeps an answer's encoding to
// itself): the file the build brotlied, sent as it is and said to be brotli.

const env = { PUBLIC_ORIGIN: "https://app.example", BETA_ORIGIN: "https://beta.example" };
const app = "// the app, as mbui-web built it";
const files = (request: Request): Response => {
  const path = new URL(request.url).pathname;
  if (path === "/mbui/app.js") return new Response(app, { headers: { "content-type": "text/javascript" } });
  if (path === "/mbui/app.js.br") return new Response(brotliCompressSync(app));
  return new Response("<title>still.fail</title>", { headers: { "content-type": "text/html; charset=utf-8" } });
};

test("the app's script goes as its build brotlied it, said to be brotli, to a browser that takes it", async () => {
  for (const origin of [env.PUBLIC_ORIGIN, env.BETA_ORIGIN]) {
    const answer = await serveWeb(new Request(`${origin}/mbui/app.js?b=1`, { headers: { "accept-encoding": "gzip, br" } }), env, files);
    assert.equal(answer.headers.get("content-encoding"), "br", origin);
    assert.equal(answer.headers.get("content-type"), "text/javascript", origin);
    assert.equal(answer.headers.get("content-length"), null, origin);
    assert.equal(brotliDecompressSync(Buffer.from(await answer.arrayBuffer())).toString(), app, origin);
    const plain = await serveWeb(new Request(`${origin}/mbui/app.js?b=1`, { headers: { "accept-encoding": "gzip" } }), env, files);
    assert.equal(plain.headers.get("content-encoding"), null, origin);
    assert.equal(await plain.text(), app, origin);
  }
});
