// Static generation of the official site: after `vp build` (the page and its scripts, dist/site) and its server build
// (web/src/site/prerender.tsx, dist/site-ssr), the page's HTML goes into dist/site/index.html, where the scripts take
// it over. Both builds name the styles alike (vanilla-extract, production), so what is built matches what hydrates.
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

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
const { render } = await import(pathToFileURL(dist("site-ssr/prerender.js")).href);
// STILLFAIL_SITE=beta: the test channel's site, youdid.wtf (web/vite.demo.config.ts).
// The page in Chinese at /, in English at /en/.
const root = process.env.STILLFAIL_SITE === "beta" ? "site-beta" : "site";
for (const [lang, file] of [["zh", "index.html"], ["en", "en/index.html"]]) {
  const page = dist(`${root}/${file}`);
  const html = readFileSync(page, "utf8");
  if (!html.includes("<!--site-->")) throw new Error(`${page} has no <!--site--> to fill`);
  writeFileSync(page, html.replace("<!--site-->", render(lang)));
  console.log(`prerendered ${page}`);
}
rmSync(dist("site-ssr"), { recursive: true, force: true });
// What the app started (timers, the demo's lingering topics) has nothing more to do.
process.exit(0);
