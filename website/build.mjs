// Builds the site for deploy into dist/website: one page per locale (English at /, the others under their prefix, as
// listed in i18n/locales.json), each with its stylesheet and script inlined (one request before the first paint),
// comments and indentation dropped; the assets copied as they are, with long cache headers for the font.
// No dependencies.
//
//   node website/build.mjs                 build every locale (a missing translation falls back to English, with a warning)
//   node website/build.mjs --strict        … and fail on a missing translation
//   node website/build.mjs --check [loc…]  list missing / extra / stale keys, markup mismatches and glyphs; exit 1 on any
//   node website/build.mjs --extract [f]   write { key: English } for translators (default dist/i18n/en-source.json)
//   node website/build.mjs --rekey         give new or edited English in index.html its key (data-t="" or a stale hash)
//
// index.html is the template, in English. Every translatable piece carries its key: an element's content data-t="key",
// an attribute data-t-<name>="key" (data-t-aria for aria-label). Keys are "<section>.<first words>.<hash>", the hash
// taken from the English, so editing the English makes the key stale and its translations drop out until the English
// is translated again (see README.md, "Languages"). The folder itself also works unbuilt on any static host, in English.
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));

// ---------- Locales and dictionaries ----------

export function loadConfig() {
  const cfg = JSON.parse(readFileSync(here("i18n/locales.json"), "utf8"));
  if (!cfg.locales.some((l) => l.code === cfg.default)) throw new Error("locales.json: the default locale is not listed");
  return cfg;
}
export function loadDict(code) {
  const f = here(`i18n/${code}.json`);
  return existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : {};
}
export const pageUrl = (cfg, loc) => cfg.origin + loc.prefix;

// ---------- Sites ----------

/** The sites the page is built for (cloud/deploy.py: `site` and `site-beta` of still.fail's cloud and of monoid's):
 *  each its name, the web app it opens, and the cloud its apps download from (the beta apps on a test channel's site).
 *  The template is monoid.build's; --site names another. */
export const SITES = {
  "monoid.build": { name: "monoid", app: "https://app.monoid.build", cloud: "https://app.monoid.build", beta: false },
  "monoid.zone": { name: "monoid", app: "https://app.monoid.zone", cloud: "https://app.monoid.build", beta: true },
  "still.fail": { name: "still.fail", app: "https://app.still.fail", cloud: "https://app.still.fail", beta: false },
  "youdid.wtf": { name: "youdid.wtf", app: "https://app.youdid.wtf", cloud: "https://app.still.fail", beta: true },
};
export const TEMPLATE_SITE = "monoid.build";

/** A page of the template's site as `site` has it: the downloads its cloud's (-beta on a test channel), the web app
 *  its own, its share cards and Android code (assets/og/<site>/, assets/android-qr-<site>.svg), every other
 *  monoid.build its host, and monoid standing alone its name (not a part of a host, a path or a stored key:
 *  monoid.site.locale stays). */
export function rebrand(html, site) {
  if (site === TEMPLATE_SITE) return html;
  const { name, app, cloud, beta } = SITES[site];
  return html
    .replace(/https:\/\/app\.monoid\.build(\/releases\/latest\/(?:mac|win|android)\b|\/(?:<wbr>)?install\.sh)?/g,
      (_, path) => (!path ? app : path.startsWith("/releases") ? `${cloud}${path}${beta ? "-beta" : ""}` : cloud + path))
    .replaceAll("/assets/og/", `/assets/og/${site}/`)
    .replaceAll("/assets/android-qr.svg", `/assets/android-qr-${site}.svg`)
    .replace(/(?<![\w.-])monoid\.build(?![\w-])/g, site)
    .replace(/(?<![\w./-])monoid(?![\w-]|\.\w)/g, name);
}

// ---------- Keys ----------

/** Text as it is stored and handed to translators: whitespace runs as one space (a space at either end matters: it
 *  separates the piece from what follows it). Hashed without the spaces at the ends. */
export const squash = (s) => s.replace(/\s+/g, " ");
export const norm = (s) => squash(s).trim();
const decode = (s) => s.replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
  .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&#x([\da-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
  .replace(/&amp;/g, "&");
export const textOf = (html) => decode(html.replace(/<[^>]*>/g, ""));
export const slugify = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().split(" ").filter(Boolean).slice(0, 4).join("-").slice(0, 40) || "x";
export const hashOf = (en) => createHash("sha1").update(norm(en)).digest("hex").slice(0, 4);
export const keyFor = (section, en) => `${section}.${slugify(textOf(en))}.${hashOf(en)}`;
const keyHash = (k) => k.slice(k.lastIndexOf(".") + 1);

/** The section a position in the template belongs to: the latest `============ Name ============` comment (its name up
 *  to a colon, without a leading number) or <section id="…"> before it; inside an element with data-i18n-section, that
 *  name. Before the first one: "meta" (the head). */
export function sectionsOf(html) {
  const marks = [];
  for (const m of html.matchAll(/<!--\s*={4,}\s*([^=]+?)\s*={4,}\s*-->/g)) marks.push([m.index, slugify(m[1].split(":")[0].replace(/^\d+\s+/, ""))]);
  for (const m of html.matchAll(/<section\b[^>]*?\sid="([^"]+)"/g)) marks.push([m.index, m[1]]);
  marks.sort((a, b) => a[0] - b[0]);
  const scopes = [];
  for (const m of html.matchAll(/<([a-z][\w-]*)\b[^>]*?\sdata-i18n-section="([^"]+)"[^>]*>/g)) {
    const [, end] = closeOf(html, m[1], m.index + m[0].length);
    scopes.push([m.index, end, m[2]]);
  }
  return (pos) => {
    const s = scopes.findLast(([a, b]) => pos >= a && pos < b);
    if (s) return s[2];
    let name = "meta";
    for (const [at, n] of marks) { if (at > pos) break; name = n; }
    return name;
  };
}

// ---------- The template's units ----------

/** Where the element whose open tag ends at `from` closes: [start of its closing tag, end of it]. */
function closeOf(html, tag, from) {
  const re = new RegExp(`<(/?)${tag}\\b(?:[^>"]|"[^"]*")*?(/?)>`, "g");
  re.lastIndex = from;
  let depth = 1, m;
  while ((m = re.exec(html))) {
    if (m[1]) depth--; else if (!m[2]) depth++;
    if (!depth) return [m.index, re.lastIndex];
  }
  throw new Error(`<${tag}> at ${from}: not closed`);
}
/** An open tag (attribute values are always double-quoted in index.html). */
const TAG_SRC = String.raw`<([a-zA-Z][\w-]*)((?:\s+[^\s=>/]+(?:="[^"]*")?)*)\s*\/?>`;
const TAG = new RegExp(TAG_SRC, "g"), TAG_AT = new RegExp(TAG_SRC, "y");
/** data-t-<name> → the attribute it translates. */
export const attrName = (n) => (n === "aria" ? "aria-label" : n);

/** Every unit in the template, in order: { key, kind: "el" | "attr", attr?, en, at } (en = the inner HTML or the raw
 *  attribute value; at = where its open tag starts; start/end = the inner HTML's span, for elements). */
export function unitsOf(html) {
  const out = [];
  for (const m of html.matchAll(TAG)) {
    const [whole, tag, attrs] = m;
    if (!attrs.includes(" data-t")) continue;
    const el = /\sdata-t="([^"]*)"/.exec(attrs);
    if (el) {
      const from = m.index + whole.length, [end] = closeOf(html, tag, from);
      out.push({ key: el[1], kind: "el", tag, en: html.slice(from, end), start: from, end, at: m.index });
    }
    for (const a of attrs.matchAll(/\sdata-t-([a-z-]+)="([^"]*)"/g)) {
      const name = attrName(a[1]), v = new RegExp(`\\s${name}="([^"]*)"`).exec(attrs);
      if (!v) throw new Error(`<${tag} data-t-${a[1]}="${a[2]}">: no ${name} attribute`);
      out.push({ key: a[2], kind: "attr", attr: a[1], tag, en: v[1], at: m.index });
    }
  }
  return out;
}

/** One entry per key; the same key twice must carry the same English. */
export function englishOf(units) {
  const en = {};
  for (const u of units) {
    if (!u.key) continue;
    if (u.key in en && en[u.key] !== squash(u.en)) throw new Error(`${u.key}: two different English texts`);
    en[u.key] ??= squash(u.en);
  }
  return en;
}

/** Units whose key's hash no longer matches their English (the English was edited), and units still without a key. */
export const staleUnits = (units) => units.filter((u) => !u.key || keyHash(u.key) !== hashOf(u.en));

// ---------- Markup a translation must keep ----------

/** The tags of a fragment that carry meaning, sorted: everything but the typographic ones a language may add or drop
 *  (<br>, <wbr>, <span class="nb"> no-break groups, <span class="vh"> visually hidden). Links keep their href. */
const TYPO = /^<(?:br|wbr)\b|^<span class="(?:nb|vh)">$/;
export function markupOf(html) {
  return (html.match(/<[a-zA-Z][^>]*>/g) || [])
    .filter((t) => !TYPO.test(t))
    .map((t) => { const n = /^<([a-zA-Z][\w-]*)/.exec(t)[1].toLowerCase(), h = /\shref="([^"]*)"/.exec(t); return h ? `${n}[href=${h[1]}]` : n; })
    .sort().join(" ");
}

// ---------- Glyphs ----------

/** Suisse Intl's unicode-range (css/00-base.css); everything else must be CJK, kana, Hangul or full-width, which the
 *  system's fonts draw. */
function suisseRanges() {
  const css = readFileSync(here("css/00-base.css"), "utf8");
  const face = /@font-face\s*{[^}]*"Suisse Intl"[^}]*unicode-range:\s*([^;}]+)/.exec(css);
  if (!face) throw new Error("css/00-base.css: no Suisse Intl unicode-range");
  return face[1].split(",").map((r) => r.trim().replace(/^U\+/i, "").split("-").map((h) => parseInt(h, 16))).map(([a, b]) => [a, b ?? a]);
}
const CJK = [[0x1100, 0x11FF], [0x2E80, 0x2FDF], [0x3000, 0x303F], [0x3040, 0x30FF], [0x3100, 0x312F], [0x3130, 0x318F],
  [0x31F0, 0x31FF], [0x3200, 0x33FF], [0x3400, 0x4DBF], [0x4E00, 0x9FFF], [0xA960, 0xA97F], [0xAC00, 0xD7AF],
  [0xD7B0, 0xD7FF], [0xF900, 0xFAFF], [0xFE10, 0xFE1F], [0xFE30, 0xFE4F], [0xFF00, 0xFFEF], [0x20000, 0x3134F]];
/** Drawn by the system's monospace font, in the terminal pictures. */
const MONO = new Set(["\u2713"]);
export function glyphProblems(dict) {
  const ok = [...suisseRanges(), ...CJK], bad = {};
  for (const [k, v] of Object.entries(dict)) for (const ch of textOf(v)) {
    const c = ch.codePointAt(0);
    if (c === 0x0A || MONO.has(ch) || ok.some(([a, b]) => c >= a && c <= b)) continue;
    (bad[ch] ??= []).push(k);
  }
  return bad;
}

// ---------- What each page gets ----------

const esc = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

/** The share card: assets/og/<code>.png (1200x630, the page's hero), else the default locale's (another site's under
 *  og/<site>/: rebrand). */
const ogImage = (cfg, loc) => `${cfg.origin}/assets/og/${existsSync(here(`assets/og/${loc.code}.png`)) ? loc.code : cfg.default}.png`;

/** <head> tags naming the page and its translations. */
export function headTags(cfg, loc) {
  const def = cfg.locales.find((l) => l.code === cfg.default);
  return [
    `<link rel="canonical" href="${pageUrl(cfg, loc)}">`,
    ...cfg.locales.map((l) => `<link rel="alternate" hreflang="${l.htmlLang}" href="${pageUrl(cfg, l)}">`),
    `<link rel="alternate" hreflang="x-default" href="${pageUrl(cfg, def)}">`,
    `<meta property="og:url" content="${pageUrl(cfg, loc)}">`,
    `<meta property="og:locale" content="${loc.ogLocale}">`,
    ...cfg.locales.filter((l) => l !== loc).map((l) => `<meta property="og:locale:alternate" content="${l.ogLocale}">`),
    `<meta property="og:image" content="${ogImage(cfg, loc)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
  ].join("\n");
}

/** Before the first paint (ES5): only a choice the reader made moves them. A stored locale other than this page's
 *  sends them to the same path under its prefix (search and hash kept); the old site's ?lang=zh|en and #zh|#en count
 *  as a choice (stored, then dropped from the URL); the old site's stored stillfail.site.lang (zh|en) becomes
 *  monoid.site.locale. First visits and crawlers stay where they asked to be. */
export function redirectScript(cfg) {
  const P = Object.fromEntries(cfg.locales.map((l) => [l.htmlLang, l.prefix]));
  const C = Object.fromEntries(cfg.locales.map((l) => [l.code, l.htmlLang]));
  return `(function(){var d=document.documentElement,l=location,P=${JSON.stringify(P)},C=${JSON.stringify(C)},K="monoid.site.locale",q=l.search,h=l.hash,w,o,m,c,r;`
    + `function g(k){try{return localStorage.getItem(k)}catch(e){return null}}function s(k,v){try{localStorage.setItem(k,v)}catch(e){}}`
    + `m=/[?&]lang=(zh|en)(?=&|$)/i.exec(q);o=h==="#zh"||h==="#en";`
    + `if(m||o){w=(m?m[1]:h.slice(1)).toLowerCase()==="zh"?"zh-CN":"en";s(K,w);if(m)q=q.replace(/([?&])lang=[^&]*&?/i,"$1").replace(/[?&]$/,"");if(o)h=""}`
    + `else{w=g(K);if(!w){o=g("stillfail.site.lang");if(o==="zh"||o==="en"){w=o==="zh"?"zh-CN":"en";s(K,w)}}}`
    + `w=C.hasOwnProperty(w)?C[w]:d.lang;`
    + `if(w!==d.lang&&P.hasOwnProperty(d.lang)){c=P[d.lang];r=l.pathname;r=r.indexOf(c)===0?r.slice(c.length):"";l.replace(P[w]+r+q+h)}`
    + `else if(q!==l.search||h!==l.hash){try{history.replaceState(history.state,"",l.pathname+q+h)}catch(e){}}})()`;
}

/** The language menu in the footer: a button and its popover, the current locale checked. */
export function switcherHTML(cfg, loc, t) {
  const word = "Language", label = t(word);
  const rows = cfg.locales.map((l) =>
    `          <a class="language-option" role="menuitemradio" aria-checked="${l === loc}" hreflang="${l.htmlLang}" data-locale="${l.code}" href="${l.prefix}">`
    + `<span lang="${l.htmlLang}">${l.label}</span><svg class="ico" aria-hidden="true"><use href="#i-check"/></svg></a>`);
  return [
    `      <div class="footer-prefs">`,
    `        <button class="language-trigger" type="button" popovertarget="languages" aria-haspopup="menu" aria-expanded="false" aria-label="${esc(label)}: ${loc.label}">`
    + `<svg class="ico" aria-hidden="true"><use href="#i-globe"/></svg><span lang="${loc.htmlLang}">${loc.label}</span><svg class="ico chev" aria-hidden="true"><use href="#i-chev"/></svg></button>`,
    `        <div class="language-menu" id="languages" popover role="menu" aria-label="${esc(word)}" data-t-aria="${keyFor("footer", word)}">`,
    ...rows,
    `        </div>`,
    `      </div>`,
  ].join("\n");
}

/** The block between <!-- i18n:name --> and <!-- /i18n:name -->, written anew (if the template has one). */
const between = (html, name, inner) => {
  const re = new RegExp(`(<!-- i18n:${name} -->)[\\s\\S]*?(<!-- /i18n:${name} -->)`);
  return re.test(html) ? html.replace(re, (_, a, b) => `${a}\n${inner()}\n${b}`) : html;
};

/** The template with one locale's words in it (the translation of every current key; English where one is missing). */
export function render(tpl, cfg, loc, dict) {
  const isDefault = loc.code === cfg.default;
  const stale = new Set(staleUnits(unitsOf(tpl)).map((u) => u.key));
  const missing = new Set();
  const say = (key, english) => {
    if (isDefault || !key) return english;
    if (!stale.has(key) && key in dict) return dict[key];
    missing.add(key);
    return english;
  };
  let html = tpl;
  // The blocks written from locales.json.
  html = between(html, "head", () => headTags(cfg, loc));
  html = between(html, "switcher", () => switcherHTML(cfg, loc, (e) => say(keyFor("footer", e), e)));
  // Elements' content (none nests inside another), then attributes.
  let out = "", i = 0;
  for (const u of unitsOf(html)) {
    if (u.kind !== "el") continue;
    out += html.slice(i, u.start) + say(u.key, u.en);
    i = u.end;
  }
  html = out + html.slice(i);
  html = html.replace(TAG, (whole, tag, attrs) => {
    if (!attrs.includes(" data-t-")) return whole;
    let next = attrs;
    for (const a of attrs.matchAll(/\sdata-t-([a-z-]+)="([^"]*)"/g)) {
      next = next.replace(new RegExp(`(\\s${attrName(a[1])}=")([^"]*)(")`), (_, p, v, s) => p + say(a[2], v).replace(/"/g, "&quot;") + s);
    }
    return "<" + tag + next + whole.slice(1 + tag.length + attrs.length);
  });
  html = html
    .replace(/\sdata-t(?:-[a-z-]+)?="[^"]*"/g, "")
    .replace(/\sdata-i18n-section="[^"]*"/g, "")
    .replace(/<html lang="[^"]*"/, `<html lang="${loc.htmlLang}"`)
    // Terms, privacy and trademark: in Chinese at /terms…, in English at /en/terms… (still.fail's web/public).
    .replace(/href="(?:\/en)?(\/[a-z]+)" data-legal/g, (_, p) => `href="${loc.legal}${p}" data-legal`);
  return { html, missing: [...missing] };
}

// ---------- The latest release ----------

/** The newest stable release's notes (docs/releases/0.1.<n>.md, scripts/changelog.ts): its version, its date, its lines
 *  by kind. A release's notes are merged into main after the commit it is built from (.github/stable-plan.py), so the
 *  stable run's checkout lacks its own: origin/main's are read too, those of releases up to the checkout's own count
 *  (a release is the commits up to it), so a site built for an older release never names a newer one. */
export function latestRelease(root = here("..")) {
  const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  const notes = new Map();
  const dir = resolve(root, "docs/releases");
  if (existsSync(dir)) for (const f of readdirSync(dir)) notes.set(f, () => readFileSync(resolve(dir, f), "utf8"));
  let upTo = Infinity;
  try {
    if (git("rev-parse", "--is-shallow-repository").trim() !== "true") upTo = Number(git("rev-list", "--count", "HEAD")); // a shallow count is no version
    for (const f of git("ls-tree", "--name-only", "origin/main", "docs/releases/").split("\n")) {
      const name = f.slice("docs/releases/".length);
      if (name && !notes.has(name)) notes.set(name, () => git("show", `origin/main:${f}`));
    }
  } catch { /* no git, or no origin/main: the checkout's own notes */ }
  const versions = [...notes.keys()].map((f) => [/^0\.1\.(\d+)\.md$/.exec(f)?.[1], f]).filter(([n]) => n && +n <= upTo).sort((a, b) => b[0] - a[0]);
  if (!versions.length) return null;
  const text = notes.get(versions[0][1])();
  const front = (key) => new RegExp(`^${key}:\\s*(\\S+)`, "m").exec(text.split("\n---", 1)[0])?.[1];
  const lines = { new: [], improved: [], fixed: [] };
  for (const m of text.matchAll(/^- (新增|改进|修复)：(.+)$/gm)) lines[{ 新增: "new", 改进: "improved", 修复: "fixed" }[m[1]]].push(m[2].trim());
  return { version: Number(front("version")), date: front("date"), lines };
}

/** A locale's page with the release in its changelog: the version on the cover, the date in the locale's own words, how
 *  many of each kind (the bars and the headline's numbers), and, in Chinese, which the notes are written in, the first
 *  three new things, each up to its first "；" (another language has no words for them: the list is left out). */
export function withRelease(html, loc, release) {
  if (!release) return html;
  const count = (kind) => release.lines[kind].length;
  const [y, m, d] = release.date.split("-").map(Number);
  const date = new Intl.DateTimeFormat(loc.htmlLang, { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" }).format(Date.UTC(y, m - 1, d));
  const shown = [...release.lines.new, ...release.lines.improved].slice(0, 3).map((l) => esc(l.split("；")[0]));
  return html
    .replace(/(<text data-release="version"[^>]*>)[^<]*/, `$1${"0.1." + release.version}`)
    .replace(/(data-release="date">)[^<]*/, `$1${date}`)
    .replace(/(<span data-n="(\w+)">)\d+/g, (_, open, kind) => open + count(kind))
    .replace(/(style="--n:)\d+([^"]*" data-n="(\w+)")/g, (_, a, b, kind) => a + count(kind) + b)
    .replace(/(<span class="val" data-n="(\w+)">)\d+/g, (_, open, kind) => open + count(kind))
    .replace(/(<ul class="changes" data-release="lines">)[\s\S]*?(<\/ul>)/, (_, open, close) => loc.code === "zh-CN"
      ? open + shown.map((l) => `<li><svg class="ico"><use href="#i-plus"/></svg><span>${l}</span></li>`).join("") + close
      : "");
}

// ---------- Build ----------

function sheetAndScript() {
  /** styles.css is a list of @imports, one file per section (css/): each inlined in its place, its URLs (written from
   *  css/, "../assets/…") made absolute, so every locale's page finds them. */
  const sheet = readFileSync(here("styles.css"), "utf8")
    .replace(/@import url\("([^"]+)"\);/g, (_, f) => readFileSync(here(f), "utf8").replaceAll("url(../assets/", "url(/assets/"));
  if (sheet.includes("@import")) throw new Error("styles.css: an @import was not inlined");
  /** CSS without comments and indentation. The sheet has no strings or URLs containing comment markers. */
  const css = sheet
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n").map((l) => l.trim()).filter(Boolean).join("\n")
    .replace(/\s*([{};,>])\s*/g, "$1")
    .replace(/;}/g, "}");
  /** The script without whole-line comments and indentation (it has no template literals spanning lines); its lazy
   *  GSAP path made absolute. */
  const js = readFileSync(here("main.js"), "utf8")
    .split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("//")).join("\n");
  if (!js.includes('"assets/vendor/')) throw new Error("main.js: the GSAP path was not found");
  return { css, js: js.replaceAll('"assets/vendor/', '"/assets/vendor/') };
}

function finish(html, css, js, cfg) {
  html = html
    .replace("<!-- i18n:redirect -->", () => `<script>${redirectScript(cfg)}</script>`)
    .replace(/<!--(?!\[)[\s\S]*?-->/g, "")
    .replace('<link rel="stylesheet" href="styles.css">', () => `<style>${css}</style>`)
    .replace('<script src="main.js" defer></script>', () => `<script>${js}</script>`)
    .replace(/(\s(?:href|src)=")assets\//g, "$1/assets/")
    .split("\n").map((l) => l.trim()).filter(Boolean).join("\n");
  if (html.includes('href="styles.css"') || html.includes('src="main.js"')) throw new Error("index.html: stylesheet or script tag not found");
  if (/\s(?:href|src)="(?!\/|#|https?:|mailto:)/.test(html)) throw new Error("index.html: a relative URL is left; /zh/ and the others would miss it");
  return html;
}

function sitemap(cfg) {
  const def = cfg.locales.find((l) => l.code === cfg.default);
  const alts = cfg.locales.map((l) => `    <xhtml:link rel="alternate" hreflang="${l.htmlLang}" href="${pageUrl(cfg, l)}"/>`)
    .concat(`    <xhtml:link rel="alternate" hreflang="x-default" href="${pageUrl(cfg, def)}"/>`);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ...cfg.locales.map((l) => [`  <url>`, `    <loc>${pageUrl(cfg, l)}</loc>`, ...alts, `  </url>`].join("\n")),
    "</urlset>", "",
  ].join("\n");
}

/** Everything wrong with the translations: the template's stale keys and odd glyphs, then per locale. */
export function check(tpl, cfg, only = []) {
  const units = unitsOf(tpl), en = englishOf(units);
  const stale = staleUnits(units).map((u) => u.key ? `${u.key}: the English changed (run --rekey)` : `no key yet: "${norm(textOf(u.en)).slice(0, 60)}" (run --rekey)`);
  const locales = {};
  for (const loc of cfg.locales) {
    if (loc.code === cfg.default || (only.length && !only.includes(loc.code))) continue;
    const dict = loadDict(loc.code);
    const r = locales[loc.code] = { missing: [], extra: [], markup: [], glyphs: glyphProblems(dict) };
    for (const k of Object.keys(en)) if (!(k in dict)) r.missing.push(k);
    for (const k of Object.keys(dict)) if (!(k in en)) r.extra.push(k);
    for (const [k, v] of Object.entries(dict)) {
      if (!(k in en)) continue;
      const a = markupOf(en[k]), b = markupOf(v);
      if (a !== b) r.markup.push(`${k}: English has [${a}], ${loc.code} has [${b}]`);
    }
  }
  return { stale, glyphs: glyphProblems(en), locales };
}

const glyphLines = (g) => Object.entries(g).map(([ch, ks]) =>
  `U+${ch.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")} "${ch}" in ${ks.slice(0, 3).join(", ")}${ks.length > 3 ? ` …+${ks.length - 3}` : ""}`);

function main(argv) {
  const has = (f) => argv.includes(f);
  const cfg = loadConfig();
  const tplPath = here("index.html");
  const tpl = readFileSync(tplPath, "utf8");

  if (has("--rekey")) {
    const at = sectionsOf(tpl), changes = [];
    let html = tpl;
    // From the end, so the positions before stay where they were.
    for (const u of unitsOf(tpl).reverse()) {
      const want = keyFor(at(u.at), u.en);
      if (u.key === want) continue;
      changes.push(`${u.key || "(new)"} → ${want}`);
      TAG_AT.lastIndex = u.at;
      const open = TAG_AT.exec(html)[0];
      const attr = u.kind === "el" ? "data-t" : `data-t-${u.attr}`;
      html = html.slice(0, u.at) + open.replace(new RegExp(`(\\s${attr}=")[^"]*(")`), `$1${want}$2`) + html.slice(u.at + open.length);
    }
    if (changes.length) writeFileSync(tplPath, html);
    console.log(changes.length ? changes.join("\n") + "\nTranslations for the old keys no longer apply: --check lists what is missing." : "Every key is current.");
    return;
  }

  if (has("--extract")) {
    const i = argv.indexOf("--extract"), arg = argv[i + 1];
    const f = arg && !arg.startsWith("--") ? arg : here("../dist/i18n/en-source.json");
    const en = englishOf(unitsOf(tpl));
    mkdirSync(dirname(f), { recursive: true });
    writeFileSync(f, JSON.stringify(en, null, 2) + "\n");
    console.log(`${Object.keys(en).length} keys → ${f}`);
    return;
  }

  if (has("--check")) {
    const only = argv.slice(argv.indexOf("--check") + 1).filter((a) => !a.startsWith("--"));
    const r = check(tpl, cfg, only);
    let bad = 0;
    const list = (title, xs) => { if (!xs.length) return; bad += xs.length; console.log(`  ${title} (${xs.length}):`); for (const x of xs) console.log(`    ${x}`); };
    console.log("index.html (en)");
    list("stale or without a key", r.stale);
    list("characters outside Suisse Intl and CJK", glyphLines(r.glyphs));
    if (!r.stale.length && !Object.keys(r.glyphs).length) console.log("  ok");
    for (const [code, x] of Object.entries(r.locales)) {
      console.log(code);
      list("missing", x.missing);
      list("extra (no such key in index.html)", x.extra);
      list("markup differs from the English", x.markup);
      list("characters outside Suisse Intl and CJK", glyphLines(x.glyphs));
      if (!x.missing.length && !x.extra.length && !x.markup.length && !Object.keys(x.glyphs).length) console.log("  ok");
    }
    process.exitCode = bad ? 1 : 0;
    return;
  }

  // The page's own faces, which it preloads and its sheet names: Suisse Intl's three subsets and Newsreader's.
  const faces = ["suisse-intl-medium", "suisse-intl-regular", "suisse-intl-book", "newsreader-400"];
  const missingFonts = faces.filter((f) => !existsSync(here(`assets/fonts/${f}.woff2`)));
  if (missingFonts.length) throw new Error(`website/assets/fonts: missing ${missingFonts.join(", ")}`);

  const r = check(tpl, cfg);
  if (r.stale.length) console.warn(`! index.html: ${r.stale.length} piece(s) of English without a current key; their translations are not used (run --rekey)`);
  if (Object.keys(r.glyphs).length) console.warn(`! index.html: characters outside Suisse Intl and CJK: ${Object.keys(r.glyphs).join(" ")}`);
  let fail = false;
  for (const [code, x] of Object.entries(r.locales)) {
    if (x.markup.length) { fail = true; console.error(`✗ ${code}: the markup differs from the English in ${x.markup.length} key(s):\n  ${x.markup.join("\n  ")}`); }
    if (x.extra.length) console.warn(`! ${code}: ${x.extra.length} key(s) no longer in index.html: ${x.extra.slice(0, 5).join(", ")}${x.extra.length > 5 ? " …" : ""}`);
    if (Object.keys(x.glyphs).length) console.warn(`! ${code}: characters outside Suisse Intl and CJK:\n  ${glyphLines(x.glyphs).join("\n  ")}`);
  }
  if (fail) throw new Error("a translation changes the markup (see above; node website/build.mjs --check)");

  // Which site (SITES) and where to: by default monoid.build's, in dist/website.
  const opt = (f) => (argv.includes(f) ? argv[argv.indexOf(f) + 1] : undefined);
  const site = opt("--site") ?? TEMPLATE_SITE;
  if (!(site in SITES)) throw new Error(`--site: no such site ${site} (of ${Object.keys(SITES).join(", ")})`);
  cfg.origin = `https://${site}`;
  const outDir = opt("--out") ?? "dist/website";
  const out = resolve(here(".."), outDir) + "/";
  const { css, js } = sheetAndScript();
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  const kb = (n) => (n / 1024).toFixed(1) + " KB", bytes = (s) => Buffer.byteLength(s);
  const release = latestRelease();
  console.log(release ? `release 0.1.${release.version} (${release.date}) in the changelog` : "! no release notes: the changelog as the template has it");
  for (const loc of cfg.locales) {
    const rendered = render(tpl, cfg, loc, loadDict(loc.code)), html = withRelease(rendered.html, loc, release), { missing } = rendered;
    if (missing.length) {
      const msg = `${loc.code}: ${missing.length} key(s) not translated, shown in English: ${missing.slice(0, 4).join(", ")}${missing.length > 4 ? " … (--check lists them all)" : ""}`;
      if (has("--strict")) throw new Error(msg);
      console.warn("! " + msg);
    }
    const dir = out + loc.prefix.slice(1);
    mkdirSync(dir, { recursive: true });
    const page = rebrand(finish(html, css, js, cfg), site);
    writeFileSync(dir + "index.html", page);
    console.log(`${outDir}${loc.prefix}index.html`.padEnd(36) + `${kb(bytes(page))}  (gzip ${kb(gzipSync(page).length)})`);
  }
  // The assets, of the share cards and Android codes only this site's (the template's: og/*.png, android-qr.svg).
  const notMine = (rel) => {
    const of = /^\/og\/([^/]+)$/.exec(rel)?.[1] ?? /^\/android-qr-(.+)\.svg$/.exec(rel)?.[1];
    if (of && of in SITES) return of !== site;
    return site !== TEMPLATE_SITE && (/^\/og\/[^/]+\.png$/.test(rel) || rel === "/android-qr.svg");
  };
  cpSync(here("assets"), out + "assets", { recursive: true, filter: (f) => !notMine(f.slice(here("assets").length)) });
  // A test channel's site has the beta apps' icon (still.fail's web/public, as the web app has it).
  if (SITES[site].beta) {
    for (const [from, to] of [["favicon-beta.svg", "favicon.svg"], ["favicon-beta-32.png", "favicon-32.png"], ["apple-touch-icon-beta.png", "apple-touch-icon.png"]]) {
      cpSync(here(`../web/public/${from}`), out + `assets/${to}`);
    }
  }
  // Terms, privacy and trademark, the pages the footer links (still.fail's web/public: in Chinese at /terms…, in
  // English at /en/terms…), with the sheet and icon they ask for at the root.
  for (const f of ["terms", "privacy", "trademark"]) {
    cpSync(here(`../web/public/${f}.html`), out + `${f}.html`);
    cpSync(here(`../web/public/en/${f}.html`), out + `en/${f}.html`);
  }
  cpSync(here("../web/public/legal.css"), out + "legal.css");
  cpSync(out + "assets/favicon.svg", out + "favicon.svg");
  // The old English address, sending to /.
  writeFileSync(out + "en/index.html", rebrand(readFileSync(here("en/index.html"), "utf8"), site));
  writeFileSync(out + "sitemap.xml", sitemap(cfg));
  writeFileSync(out + "robots.txt", existsSync(here("robots.txt")) ? readFileSync(here("robots.txt"), "utf8")
    : `User-agent: *\nAllow: /\n\nSitemap: ${cfg.origin}/sitemap.xml\n`);
  // Cloudflare / Netlify style headers: the fonts are named for good; the other assets for a day; the pages are asked
  // for each time. Those hosts apply every rule that matches and join a header set twice, so no two rules here set
  // Cache-Control for the same path ("*" spans slashes: /assets/*.png covers the og images too).
  writeFileSync(out + "_headers", [
    "/assets/fonts/*", "  Cache-Control: public, max-age=31536000, immutable",
    ...["/assets/*.svg", "/assets/*.png", "/assets/vendor/*"].flatMap((p) => [p, "  Cache-Control: public, max-age=86400"]),
    "/*", "  X-Content-Type-Options: nosniff", "",
  ].join("\n"));
  for (const f of faces) console.log(`${f.padEnd(36)}${kb(statSync(out + `assets/fonts/${f}.woff2`).size)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv.slice(2));
