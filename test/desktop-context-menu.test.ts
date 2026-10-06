import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { contextMenu, type Clicked, type Item } from "../apps/desktop/src/context-menu.mts";

const ORIGINS = { app: "app://stillfail", cloud: "https://app.still.fail" };

/** A right-click on nothing in particular: the page's background. */
const nothing: Clicked = {
  linkURL: "", srcURL: "", mediaType: "none", hasImageContents: false, selectionText: "", isEditable: false,
  editFlags: { canCut: false, canCopy: false, canPaste: false, canSelectAll: true },
};
const menu = (clicked: Partial<Clicked>, origins = ORIGINS) => contextMenu({ ...nothing, ...clicked }, origins);
/** The menu as its items' names, "-" for a line. */
const names = (items: Item[]) => items.map((item) => (item ? item.key.replace("desktop.contextMenu.", "") : "-"));

test("the page's background has nothing to offer: no menu", () => {
  assert.deepEqual(menu({}), []);
});

test("a chat's image is copied, the whole of it its thumbnail stands in for; its address, the page's own, is not offered", () => {
  const items = menu({ mediaType: "image", srcURL: "blob:app://stillfail/1f0e", hasImageContents: true });
  assert.deepEqual(items, [{ key: "desktop.contextMenu.copyImage", action: { do: "copyImage", whole: true }, enabled: true }]);
  // Not loaded yet, or failed to: nothing to copy.
  assert.equal(menu({ mediaType: "image", srcURL: "blob:app://stillfail/1f0e" })[0]?.enabled, false);
  // Run from a dev server (dev.sh HMR=1), the page's pictures are blob:http://….
  const dev = { app: "http://192.168.1.5:5173", cloud: "https://app.still.fail" };
  assert.deepEqual(menu({ mediaType: "image", srcURL: "blob:http://192.168.1.5:5173/1f0e", hasImageContents: true }, dev)[0]?.action, { do: "copyImage", whole: true });
});

test("an image on the web is copied as shown, or its address", () => {
  const src = "https://lh3.googleusercontent.com/a/photo";
  const items = menu({ mediaType: "image", srcURL: src, hasImageContents: true });
  assert.deepEqual(names(items), ["copyImage", "copyImageAddress"]);
  assert.deepEqual(items[0]?.action, { do: "copyImage", whole: false });
  assert.deepEqual(items[1]?.action, { do: "copyText", text: src });
  // A picture of a page in a preview (a station's web service) is that page's, not one of the app's.
  assert.deepEqual(menu({ mediaType: "image", srcURL: "blob:stillfail-preview://p3000-0123456789ab/77aa", hasImageContents: true })[0]?.action, { do: "copyImage", whole: false });
});

test("a link on the web opens in the browser or is copied; the word macOS selects under the pointer is copied", () => {
  const url = "https://github.com/AFK-surf/still.fail/pull/1";
  const items = menu({ linkURL: url, selectionText: "pull" });
  assert.deepEqual(names(items), ["openLink", "copyLink", "-", "copy"]);
  assert.deepEqual(items[0]?.action, { do: "open", url });
  assert.deepEqual(items[1]?.action, { do: "copyText", text: url });
});

test("a link to a page of the app is copied as that page on the web, and not opened in a browser", () => {
  assert.deepEqual(menu({ linkURL: "app://stillfail/o/ws/st/chat?service=web" }), [
    { key: "desktop.contextMenu.copyLink", action: { do: "copyText", text: "https://app.still.fail/o/ws/st/chat?service=web" }, enabled: true },
  ]);
  // Run from a dev server (dev.sh HMR=1), the app's pages are on plain http: still the app's own.
  const dev = { app: "http://192.168.1.5:5173", cloud: "https://app.still.fail" };
  assert.deepEqual(menu({ linkURL: "http://192.168.1.5:5173/settings" }, dev), [
    { key: "desktop.contextMenu.copyLink", action: { do: "copyText", text: "https://app.still.fail/settings" }, enabled: true },
  ]);
});

test("a link to anything else (a file's download, mail, a preview's page) offers nothing of its own", () => {
  for (const linkURL of ["blob:app://stillfail/77aa", "mailto:someone@example.com", "stillfail-preview://p3000-0123456789ab/next", "javascript:void 0"]) {
    assert.deepEqual(menu({ linkURL }), [], linkURL);
  }
});

test("an image in a link: the link's items, a line, the image's", () => {
  const items = menu({ linkURL: "https://example.com/", mediaType: "image", srcURL: "blob:app://stillfail/1f0e", hasImageContents: true });
  assert.deepEqual(names(items), ["openLink", "copyLink", "-", "copyImage"]);
});

test("words selected are copied", () => {
  assert.deepEqual(menu({ selectionText: "a reply" }), [{ key: "desktop.contextMenu.copy", action: { do: "edit", command: "copy" }, enabled: true }]);
  assert.deepEqual(menu({ selectionText: " \n" }), []);
});

test("a field is cut, copied, pasted into or all selected, as far as it can be now", () => {
  const items = menu({ isEditable: true, selectionText: "draft", editFlags: { canCut: true, canCopy: true, canPaste: false, canSelectAll: true } });
  assert.deepEqual(names(items), ["cut", "copy", "paste", "selectAll"]);
  assert.deepEqual(items.map((item) => item?.enabled), [true, true, false, true]);
  assert.deepEqual(items.map((item) => item?.action), ["cut", "copy", "paste", "selectAll"].map((command) => ({ do: "edit", command })));
});

test("every item's words are in both languages", () => {
  const keys = [
    ...menu({ linkURL: "https://example.com/", mediaType: "image", srcURL: "https://example.com/a.png", hasImageContents: true, isEditable: true }),
    ...menu({ selectionText: "words" }),
  ].flatMap((item) => (item ? [item.key] : []));
  for (const lang of ["zh", "en"]) {
    const words = JSON.parse(readFileSync(new URL(`../client/i18n/catalog/${lang}/desktop.json`, import.meta.url), "utf8")) as Record<string, unknown>;
    assert.deepEqual(keys.filter((key) => !(key in words)), [], lang);
  }
});
