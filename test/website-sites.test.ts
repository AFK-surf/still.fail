import assert from "node:assert/strict";
import { test } from "node:test";
// @ts-expect-error: the site's build is plain JavaScript (website/build.mjs), untyped
import { SITES, latestRelease, rebrand, withRelease } from "../website/build.mjs";

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
  assert.match(zone, /<title>monoid · /, "monoid.zone is named monoid, as monoid.build");
  assert.match(zone, /href="https:\/\/app\.monoid\.zone">Open monoid</);
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

// The changelog names the newest stable release (docs/releases), never the one the template was written with.
const post = [
  `<text data-release="version" x="48">0.1.7394</text><span class="tnum" data-release="date">November 6, 2026</span>`,
  `<h3><span>This release: <span data-n="fixed">12</span> fixes and <span data-n="new">5</span> new features</span></h3>`,
  `<span class="bar" style="--n:5;--c:var(--ink)" data-n="new"></span><span class="val" data-n="new">5</span>`,
  `<span class="bar" style="--n:12" data-n="fixed"></span><span class="val" data-n="fixed">12</span>`,
  `<ul class="changes" data-release="lines"><li>old</li></ul>`,
].join("");
const release = { version: 8755, date: "2026-11-14", lines: { new: ["重试按钮", "密钥库可以写说明；agent 存密钥时写清"], improved: ["更快", "更顺"], fixed: ["a", "b", "c"] } };

test("the changelog shows the latest release: its version, date and counts in every language, its lines in Chinese", () => {
  const en = withRelease(post, { code: "en", htmlLang: "en" }, release);
  assert.match(en, />0\.1\.8755</);
  assert.match(en, /data-release="date">November 14, 2026</);
  assert.match(en, /<span data-n="fixed">3<\/span> fixes and <span data-n="new">2<\/span> new/);
  assert.match(en, /style="--n:2;--c:var\(--ink\)" data-n="new"><\/span><span class="val" data-n="new">2</);
  assert.match(en, /style="--n:3" data-n="fixed"><\/span><span class="val" data-n="fixed">3</);
  assert.ok(!en.includes("changes"), "no lines where the notes have no words for them");
  const zh = withRelease(post, { code: "zh-CN", htmlLang: "zh-CN" }, release);
  assert.match(zh, /data-release="date">2026年11月14日</);
  assert.deepEqual([...zh.matchAll(/<span>([^<]*)<\/span><\/li>/g)].map((m) => m[1]), ["重试按钮", "密钥库可以写说明", "更快"]);
});

test("the newest release notes are found, with their version and lines", () => {
  const r = latestRelease();
  assert.ok(r && r.version >= 8755 && /^\d{4}-\d{2}-\d{2}$/.test(r.date));
  assert.ok(r.lines.new.length + r.lines.improved.length + r.lines.fixed.length > 0);
});
