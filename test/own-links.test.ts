import assert from "node:assert/strict";
import { test } from "node:test";
import { ownOrigin } from "../web/src/stillfailLink.ts";

const own = (href: string, here: string, cloud: string | null = null) => ownOrigin(new URL(href), here, cloud);

test("a link on any of still.fail cloud's hosts is the app's own wherever it is on that cloud", () => {
  // Agents post app.still.fail's links; a reference written on the test channel's web app names app.youdid.wtf.
  assert.ok(own("https://app.still.fail/o/ws/st/k", "https://app.youdid.wtf"));
  assert.ok(own("https://app.youdid.wtf/w/ws/s/st/chats/k", "https://app.still.fail"));
  assert.ok(own("https://ember.3720.org/o/ws/st/k", "https://app.still.fail"));
  // The desktop app's page is app://stillfail, its cloud app.still.fail.
  assert.ok(own("https://app.youdid.wtf/w/ws/s/st/chats/k", "app://stillfail", "https://app.still.fail"));
});

test("another site, or still.fail's links seen from a dev cloud, are not", () => {
  assert.ok(!own("https://example.com/o/ws/st/k", "https://app.still.fail"));
  assert.ok(!own("http://app.still.fail/o/ws/st/k", "https://app.youdid.wtf"));
  assert.ok(!own("https://app.still.fail:8443/o/ws/st/k", "https://app.youdid.wtf"));
  assert.ok(!own("https://still.fail/o/ws/st/k", "https://app.still.fail"));
  assert.ok(!own("https://app.still.fail/o/ws/st/k", "http://localhost:8787"));
  assert.ok(own("http://localhost:8787/o/ws/st/k", "http://localhost:8787"));
});
