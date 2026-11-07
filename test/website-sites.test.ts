import assert from "node:assert/strict";
import { test } from "node:test";
// @ts-expect-error: the site's build is plain JavaScript (website/build.mjs), untyped
import { SITES, rebrand } from "../website/build.mjs";

// The template is monoid.build's page; each other site is it with its name, its web app and its cloud's downloads.
const page = [
  `<title>monoid · One devices</title><a href="https://app.monoid.build">Open monoid</a>`,
  `<a href="https://app.monoid.build/releases/latest/mac">Mac</a><a href="https://app.monoid.build/releases/latest/android">Android</a>`,
  `<code>curl -fsSL https://app.monoid.build/<wbr>install.sh</code><button data-copy="curl -fsSL https://app.monoid.build/install.sh">`,
  `<link rel="canonical" href="https://monoid.build/zh/"><meta property="og:image" content="https://monoid.build/assets/og/en.png"><img src="/assets/android-qr.svg"><span>@monoid</span>`,
  `<script>K="monoid.site.locale"</script><a href="mailto:lin@acme.dev">lin@acme.dev</a>`,
].join("");

test("monoid.build's page is the template as it is", () => {
  assert.equal(rebrand(page, "monoid.build"), page);
});

test("still.fail's page is named still.fail and opens and downloads still.fail's", () => {
  assert.equal(rebrand(page, "still.fail"), [
    `<title>still.fail · One devices</title><a href="https://app.still.fail">Open still.fail</a>`,
    `<a href="https://app.still.fail/releases/latest/mac">Mac</a><a href="https://app.still.fail/releases/latest/android">Android</a>`,
    `<code>curl -fsSL https://app.still.fail/<wbr>install.sh</code><button data-copy="curl -fsSL https://app.still.fail/install.sh">`,
    `<link rel="canonical" href="https://still.fail/zh/"><meta property="og:image" content="https://still.fail/assets/og/still.fail/en.png"><img src="/assets/android-qr-still.fail.svg"><span>@still.fail</span>`,
    `<script>K="monoid.site.locale"</script><a href="mailto:lin@acme.dev">lin@acme.dev</a>`,
  ].join(""));
});

test("a test channel's page opens its own web app and downloads the beta apps from its cloud", () => {
  const zone = rebrand(page, "monoid.zone");
  assert.match(zone, /<title>monoid\.zone · /);
  assert.match(zone, /href="https:\/\/app\.monoid\.zone">Open monoid\.zone</);
  assert.match(zone, /https:\/\/app\.monoid\.build\/releases\/latest\/mac-beta"/);
  assert.match(zone, /https:\/\/app\.monoid\.build\/releases\/latest\/android-beta"/);
  assert.match(zone, /curl -fsSL https:\/\/app\.monoid\.build\/install\.sh/);
  assert.match(zone, /href="https:\/\/monoid\.zone\/zh\/"/);
  const wtf = rebrand(page, "youdid.wtf");
  assert.match(wtf, /href="https:\/\/app\.youdid\.wtf">Open youdid\.wtf</);
  assert.match(wtf, /https:\/\/app\.still\.fail\/releases\/latest\/mac-beta"/);
  assert.ok(!/monoid(?!\.site\.locale)/.test(wtf.replace("mailto:lin@acme.dev", "")), "nothing of monoid's left but its stored key");
});

test("every site has its share cards and Android code", async () => {
  const { existsSync } = await import("node:fs");
  for (const site of Object.keys(SITES).filter((s) => s !== "monoid.build")) {
    assert.ok(existsSync(new URL(`../website/assets/android-qr-${site}.svg`, import.meta.url)), `${site}: Android code`);
    for (const code of ["en", "zh-CN", "zh-TW", "ja", "ko"]) {
      assert.ok(existsSync(new URL(`../website/assets/og/${site}/${code}.png`, import.meta.url)), `${site}: share card (${code})`);
    }
  }
});
