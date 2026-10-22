import { test } from "node:test";
import assert from "node:assert/strict";
import { backPage } from "../web/src/backPage.ts";

/** The Navigation API's history as a page sees it: `entries` (whether each is this document's), the one in view `at`. */
function history(entries: boolean[], at: number) {
  const went: string[] = [];
  let land = () => {};
  (globalThis as { window?: unknown }).window = {
    navigation: {
      currentEntry: { index: at },
      entries: () => entries.map((sameDocument, i) => ({ key: `e${i}`, sameDocument })),
      traverseTo: (key: string) => { went.push(key); return { finished: new Promise<void>((resolve) => { land = resolve; }) }; },
    },
  };
  return { went, land: () => land() };
}

test("back goes to the entry before, of this page", async () => {
  const h = history([true, true, true], 2);
  const said: string[] = [];
  backPage(() => said.push("fallback"), () => said.push("outside"));
  assert.deepEqual(h.went, ["e1"]);
  assert.deepEqual(said, []);
  h.land();
  await new Promise((resolve) => setTimeout(resolve));
});

test("an entry from before the page loaded again is not gone to: that would load the whole page", () => {
  // Entries 0 and 1 are the page before a reload; 2 is this page's first, 3 the one in view.
  const h = history([false, false, true, true], 2);
  const said: string[] = [];
  backPage(() => said.push("fallback"), () => said.push("outside"));
  assert.deepEqual(h.went, []);
  assert.deepEqual(said, ["outside"]);
});

test("a second back while the first lands (Safari's swipe and the page's own) does not go back again", async () => {
  const h = history([false, true, true, true], 3);
  backPage(() => {}, () => {});
  backPage(() => {}, () => {});
  assert.deepEqual(h.went, ["e2"]);
  h.land();
  await new Promise((resolve) => setTimeout(resolve));
  backPage(() => {}, () => {});
  assert.deepEqual(h.went, ["e2", "e2"]);
  h.land();
  await new Promise((resolve) => setTimeout(resolve));
});

test("without the Navigation API, the browser's back", () => {
  (globalThis as { window?: unknown }).window = {};
  const said: string[] = [];
  backPage(() => said.push("fallback"), () => said.push("outside"));
  assert.deepEqual(said, ["fallback"]);
});
