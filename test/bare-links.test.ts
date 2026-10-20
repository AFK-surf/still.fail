import assert from "node:assert/strict";
import { test } from "node:test";
import { bareLinks } from "../web/src/bareLinks.ts";

/** The addresses found in `text`. */
const found = (text: string) => bareLinks(text).flatMap((p) => (typeof p === "string" ? [] : [p.url]));

test("a bare address ends where Chinese words or full-width marks begin", () => {
  assert.deepEqual(bareLinks("（https://github.com/AFK-surf/Cue/pull/2854）已改到"), ["（", { url: "https://github.com/AFK-surf/Cue/pull/2854" }, "）已改到"]);
  assert.deepEqual(found("PR：https://github.com/AFK-surf/still.fail/pull/134"), ["https://github.com/AFK-surf/still.fail/pull/134"]);
  assert.deepEqual(found("看下https://example.com/a，再说"), ["https://example.com/a"]);
  assert.deepEqual(found("部署好了：https://x-1.trycloudflare.com。"), ["https://x-1.trycloudflare.com"]);
  assert.deepEqual(found("https://zh.wikipedia.org/wiki/中文"), ["https://zh.wikipedia.org/wiki/"]);
});

test("the marks closing a sentence or a bracket stay outside the address", () => {
  assert.deepEqual(bareLinks("see https://example.com/a."), ["see ", { url: "https://example.com/a" }, "."]);
  assert.deepEqual(found("(see https://example.com/a)"), ["https://example.com/a"]);
  assert.deepEqual(found("https://en.wikipedia.org/wiki/Foo_(bar)"), ["https://en.wikipedia.org/wiki/Foo_(bar)"]);
  assert.deepEqual(found("(https://en.wikipedia.org/wiki/Foo_(bar))"), ["https://en.wikipedia.org/wiki/Foo_(bar)"]);
  assert.deepEqual(found("<https://example.com/a>"), ["https://example.com/a"]);
  assert.deepEqual(found("'https://example.com/a', https://example.com/b!"), ["https://example.com/a", "https://example.com/b"]);
  assert.deepEqual(found("https://example.com/docs/deploy?ref=still.fail&tab=android#step-3，打开"), ["https://example.com/docs/deploy?ref=still.fail&tab=android#step-3"]);
});

test("what is not an address to open stays words", () => {
  for (const text of ["https://", "https://。", "xhttps://example.com", "https://github.com/…", "www.example.com", "a@b.co", "ftp://example.com"]) {
    assert.deepEqual(bareLinks(text), [text], text);
  }
  assert.deepEqual(bareLinks(""), []);
  assert.deepEqual(found("two: http://a.io/x https://b.io/y"), ["http://a.io/x", "https://b.io/y"]);
});
