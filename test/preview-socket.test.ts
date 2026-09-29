// cloud/src/previewSocket.ts: where a service's page gets the script for its WebSockets, however its bytes come apart.
import { test } from "node:test";
import assert from "node:assert/strict";
import { withSocketTag } from "../cloud/src/previewSocket.ts";

const TAG = '<script src="/_ember/socket.js"></script>';

async function tagged(parts: string[]): Promise<string> {
  const bytes = parts.map((p) => new TextEncoder().encode(p));
  const body = new ReadableStream<Uint8Array>({ start(c) { for (const b of bytes) c.enqueue(b); c.close(); } });
  return new Response(withSocketTag(body)).text();
}

test("the script goes after <html> or <head>, however the page's first bytes are cut", async () => {
  const page = "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"></head><body>hi</body></html>";
  const html = page.indexOf("<head>");
  const head = html + "<head>".length;
  for (const parts of [...Array.from({ length: page.length - 1 }, (_, i) => [page.slice(0, i + 1), page.slice(i + 1)]), [...page]]) {
    const got = await tagged(parts);
    assert.equal(got.replace(TAG, ""), page, "the page as it was, the script added");
    assert.ok([html, head].includes(got.indexOf(TAG)), `after <html> or <head> (${parts.length} pieces, the first ${parts[0]!.length} long): ${got}`);
  }
  assert.equal(await tagged([page]), page.replace("<head>", "<head>" + TAG), "all at once: after <head>");
});

test("no <head>: after <html>, else after the doctype, else first; never before a doctype", async () => {
  assert.equal(await tagged(["<!doc", "type html><html><body>x"]), `<!doctype html><html>${TAG}<body>x`);
  assert.equal(await tagged(["<!DOCTYPE html>", "<p>x"]), `<!DOCTYPE html>${TAG}<p>x`);
  assert.equal(await tagged(["<p>x</p>"]), `${TAG}<p>x</p>`);
  assert.equal(await tagged([]), "", "an empty page stays empty");
});
