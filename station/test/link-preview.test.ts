// A web link's preview (src/links/preview.ts): what a page's head says, and which addresses are fetched at all.
import assert from "node:assert/strict";
import { test } from "node:test";
import { bodyUpTo, headOf, htmlText, isPublic, linkPreview, oembedOf } from "../src/links/preview.ts";

test("a page's head: og first, else its title; its icon, else /favicon.ico", () => {
  const base = new URL("https://ex.am/docs/page");
  const html = `<html><head><title>Plain &amp; simple</title><meta property="og:title" content="The &quot;real&quot; title">
    <meta name=description content='What it is'><meta property="og:site_name" content="Example"><link rel="icon" href="/i.png"></head><body><title>no</title></body>`;
  assert.deepEqual(headOf(html, base), { title: 'The "real" title', description: "What it is", site: "Example", icon: "https://ex.am/i.png" });
  assert.deepEqual(headOf("<title> A&#x26;B  &#169; </title>", base), { title: "A&B ©", icon: "https://ex.am/favicon.ico" });
  assert.equal(htmlText("a&nbsp;b &bogus; c"), "a b &bogus; c");
});

test("a page's picture: og:image (its &amp; read), else twitter:image, by the page's address; only a web one", () => {
  const base = new URL("https://ex.am/docs/page");
  const og = `<head><title>T</title><meta property="og:image" content="https://cdn.ex.am/p.jpg?a=1&amp;b=2"><meta name="twitter:image" content="/t.png"></head>`;
  assert.equal(headOf(og, base).image, "https://cdn.ex.am/p.jpg?a=1&b=2");
  assert.equal(headOf(`<title>T</title><meta name="twitter:image" content="../t.png">`, base).image, "https://ex.am/t.png");
  assert.equal(headOf(`<title>T</title><meta property="og:image" content="javascript:alert(1)">`, base).image, undefined);
  assert.equal(headOf(`<head><title>T</title></head><meta property="og:image" content="/after.png">`, base).image, undefined);
});

test("a video link is asked of its site's oEmbed; any other is not", () => {
  const of = (s: string) => oembedOf(new URL(s));
  for (const s of ["https://www.youtube.com/watch?v=7YiXO6twfXk", "https://m.youtube.com/watch?v=x", "https://youtu.be/7YiXO6twfXk", "https://www.youtube.com/shorts/abc"]) {
    assert.equal(of(s), `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(s)}`, s);
  }
  assert.equal(of("https://vimeo.com/76979871"), `https://vimeo.com/api/oembed.json?url=${encodeURIComponent("https://vimeo.com/76979871")}`);
  for (const s of ["https://www.youtube.com/", "https://www.youtube.com/@channel", "https://youtu.be/", "https://vimeo.com/about", "https://notyoutube.com/watch?v=x"]) assert.equal(of(s), null, s);
});

test("a page is read up to its head's end, even when the tag is cut between chunks", async () => {
  const chunks = ["<html><head><title>T</title></he", "ad><body>", "x".repeat(1000)];
  let pulled = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(c) {
      if (pulled < chunks.length) c.enqueue(new TextEncoder().encode(chunks[pulled++]!));
      else c.close();
    },
  });
  const read = (await bodyUpTo(new Response(body), 1 << 20, /<\/head>/i)).toString("utf8");
  assert.equal(read, chunks[0]! + chunks[1]!);
});

test("only the internet's addresses are fetched", async () => {
  for (const a of ["127.0.0.1", "10.1.2.3", "192.168.1.1", "172.20.0.1", "169.254.1.1", "100.64.0.1", "0.0.0.0", "::1", "fd00::1", "fe80::1", "::ffff:127.0.0.1"]) assert.equal(isPublic(a), false, a);
  for (const a of ["1.1.1.1", "140.82.112.3", "2606:4700::1111"]) assert.equal(isPublic(a), true, a);
  assert.equal(await linkPreview("http://127.0.0.1:1/"), null);
  assert.equal(await linkPreview("http://localhost:1/x"), null);
  assert.equal(await linkPreview("file:///etc/passwd"), null);
});
