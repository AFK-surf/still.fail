// Static generation of the official site: after `vite build` (the page and its scripts, dist/site) and its server build
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
  // A document with no body: what the app would put on the page (the sidebar's buddy) is drawn in place (brand.tsx).
  document: { documentElement: { dataset: { theme: "dark" } }, body: null, getElementById: () => null, querySelector: () => null, addEventListener: noop, removeEventListener: noop },
});

const dist = (path) => fileURLToPath(new URL(`../dist/${path}`, import.meta.url));
const { render } = await import(pathToFileURL(dist("site-ssr/prerender.js")).href);
const page = dist("site/index.html");
const html = readFileSync(page, "utf8");
if (!html.includes("<!--site-->")) throw new Error("dist/site/index.html has no <!--site--> to fill");
writeFileSync(page, html.replace("<!--site-->", render()));
rmSync(dist("site-ssr"), { recursive: true, force: true });
console.log("prerendered dist/site/index.html");
// What the app started (timers, the demo's lingering topics) has nothing more to do.
process.exit(0);
