// Static generation of the official site: after `vp build` (the page and its scripts, dist/site) and its server build
// (web/src/site/prerender.tsx, dist/site-ssr), the page's HTML goes into dist/site/index.html, where the scripts take
// it over. Both builds name the styles alike (vanilla-extract, production), so what is built matches what hydrates.
import { readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { transform } from "lightningcss";

// The app reads the browser as its modules load and render (the theme, stored settings, the screen's width): here it
// finds one that says nothing — light, wide, nothing stored.
const noop = () => {};
const store = () => { const m = new Map(); return { getItem: (k) => m.get(k) ?? null, setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k), clear: () => m.clear(), key: () => null, length: 0 }; };
Object.assign(globalThis, {
  window: globalThis,
  localStorage: store(),
  sessionStorage: store(),
  matchMedia: (query) => ({ matches: false, media: query, addEventListener: noop, removeEventListener: noop, addListener: noop, removeListener: noop }),
  Image: class { set src(_) {} decode() { return Promise.resolve(); } },
  requestAnimationFrame: (f) => setTimeout(f, 16),
  cancelAnimationFrame: (t) => clearTimeout(t),
  addEventListener: noop,
  removeEventListener: noop,
  // A document with no body: what the app would put on the page (更新 at the sidebar's top) is drawn in place (brand.tsx).
  document: { documentElement: { dataset: { theme: "dark" }, hasAttribute: () => false }, body: null, getElementById: () => null, getElementsByTagName: () => [], querySelector: () => null, addEventListener: noop, removeEventListener: noop },
});
// Node's own navigator says nothing of the system, where the math typesetter (MathJax, as it loads) reads appVersion.
Object.defineProperty(globalThis, "navigator", { configurable: true, value: { userAgent: "", appVersion: "", platform: "", language: "zh-CN", languages: ["zh-CN"] } });

// Node's own navigator says no appVersion, which MathJax reads as it loads (the core's formulas, client/core-ts's
// math.ts: @mathjax/src's util/context.js, which then looks for its script among the document's): one that says it, empty.
Object.defineProperty(globalThis, "navigator", { value: { userAgent: navigator.userAgent, language: navigator.language, languages: navigator.languages, platform: navigator.platform, hardwareConcurrency: navigator.hardwareConcurrency, appVersion: "" }, configurable: true });

const dist = (path) => fileURLToPath(new URL(`../dist/${path}`, import.meta.url));
const { render, renderPhone } = await import(pathToFileURL(dist("site-ssr/prerender.js")).href);
// STILLFAIL_SITE=beta: the test channel's site, youdid.wtf (web/vite.demo.config.ts).
// The page in Chinese at /, in English at /en/; the phone beside the computer on each (phone.html, en/phone.html).
const root = process.env.STILLFAIL_SITE === "beta" ? "site-beta" : "site";

// The one sheet of every style (vite.demo.config.ts cssCodeSplit), mostly the app's: a page waiting on all of it before
// its first paint waits on what it does not draw (nineteen twentieths of it, 2026-10-29). Each page has in its head the
// rules that can match what is built into it, and the whole sheet at the end of its body, which draws nothing earlier
// in the page while it comes, and which the page's scripts still wait for (a module script runs only once the sheets
// before it are in), so nothing they draw is drawn without its styles. The sheet repeats those rules, in the same order.
const sheet = readdirSync(dist(`${root}/assets`)).find((f) => /^style-.*\.css$/.test(f));
if (!sheet) throw new Error(`dist/${root}/assets has no style sheet`);
const sheetCode = readFileSync(dist(`${root}/assets/${sheet}`));
const sheetLink = new RegExp(`<link rel="stylesheet"[^>]*href="/assets/${sheet.replace(/[.]/g, "\\.")}"[^>]*>`);
/** The Latin letters' face (most of what the page says first, its title among it), asked for with the page, not once
 *  its sheet has been read and its text laid out. */
const latin = readdirSync(dist(`${root}/assets`)).find((f) => /^inter-latin-wght-normal-.*\.woff2$/.test(f));
if (!latin) throw new Error(`dist/${root}/assets has no Inter (Latin)`);

/** The classes a selector needs an element (or its ancestors) to have, outside what only qualifies it (:not, :is…). */
const needs = (selector) => selector.filter((part) => part.type === "class").map((part) => part.name);

/** The rules of the sheet that can match something in `html`: all but those whose every selector names a class it
 *  never has. */
function drawnBy(html) {
  const has = new Set([...html.matchAll(/\sclass="([^"]*)"/g)].flatMap((m) => m[1].split(/\s+/)));
  const { code } = transform({
    filename: sheet, code: sheetCode, minify: true,
    visitor: {
      // Kept as it is (returned changed, lightningcss cannot read some rules back), or left out.
      Rule: { style: (rule) => rule.value.selectors.some((s) => needs(s).every((c) => has.has(c))) ? undefined : [] },
    },
  });
  return code.toString();
}

for (const [lang, file, mark, build] of [
  ["zh", "index.html", "<!--site-->", render], ["en", "en/index.html", "<!--site-->", render],
  ["zh", "phone.html", "<!--demo-->", renderPhone], ["en", "en/phone.html", "<!--demo-->", renderPhone],
]) {
  const page = dist(`${root}/${file}`);
  const html = readFileSync(page, "utf8");
  if (!html.includes(mark)) throw new Error(`${page} has no ${mark} to fill`);
  const link = sheetLink.exec(html)?.[0];
  if (!link) throw new Error(`${page} has no link to ${sheet}`);
  const built = html.replace(mark, build(lang));
  const head = `<link rel="preload" href="/assets/${latin}" as="font" type="font/woff2" crossorigin><style>${drawnBy(built)}</style>`;
  writeFileSync(page, built.replace(link, head).replace("</body>", `${link}\n</body>`));
  console.log(`prerendered ${page}`);
}
rmSync(dist("site-ssr"), { recursive: true, force: true });
// What the app started (timers, the demo's lingering topics) has nothing more to do.
process.exit(0);
