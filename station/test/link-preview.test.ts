// A web link's preview (src/links/preview.ts): what a page's head says, and which addresses are fetched at all.
import assert from "node:assert/strict";
import { test } from "node:test";
import { headOf, htmlText, isPublic, linkPreview } from "../src/links/preview.ts";

test("a page's head: og first, else its title; its icon, else /favicon.ico", () => {
  const base = new URL("https://ex.am/docs/page");
  const html = `<html><head><title>Plain &amp; simple</title><meta property="og:title" content="The &quot;real&quot; title">
    <meta name=description content='What it is'><meta property="og:site_name" content="Example"><link rel="icon" href="/i.png"></head><body><title>no</title></body>`;
  assert.deepEqual(headOf(html, base), { title: 'The "real" title', description: "What it is", site: "Example", icon: "https://ex.am/i.png" });
  assert.deepEqual(headOf("<title> A&#x26;B  &#169; </title>", base), { title: "A&B ©", icon: "https://ex.am/favicon.ico" });
  assert.equal(htmlText("a&nbsp;b &bogus; c"), "a b &bogus; c");
});

test("only the internet's addresses are fetched", async () => {
  for (const a of ["127.0.0.1", "10.1.2.3", "192.168.1.1", "172.20.0.1", "169.254.1.1", "100.64.0.1", "0.0.0.0", "::1", "fd00::1", "fe80::1", "::ffff:127.0.0.1"]) assert.equal(isPublic(a), false, a);
  for (const a of ["1.1.1.1", "140.82.112.3", "2606:4700::1111"]) assert.equal(isPublic(a), true, a);
  assert.equal(await linkPreview("http://127.0.0.1:1/"), null);
  assert.equal(await linkPreview("http://localhost:1/x"), null);
  assert.equal(await linkPreview("file:///etc/passwd"), null);
});
