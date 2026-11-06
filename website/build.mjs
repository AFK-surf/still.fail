// Builds the site for deploy into dist/website: the page with its stylesheet and script inlined (one request before
// the first paint), comments and indentation dropped; the assets copied as they are, with long cache headers for the
// font. No dependencies: `node website/build.mjs`. The folder itself also works unbuilt on any static host.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const out = here("../dist/website/");

/** styles.css is a list of @imports, one file per section (css/): each inlined in its place, its URLs (written from
 *  css/, "../assets/…") made the page's own ("assets/…"). */
const sheet = readFileSync(here("styles.css"), "utf8")
  .replace(/@import url\("([^"]+)"\);/g, (_, f) => readFileSync(here(f), "utf8").replaceAll("url(../assets/", "url(assets/"));
if (sheet.includes("@import")) throw new Error("styles.css: an @import was not inlined");

/** CSS without comments and indentation. The sheet has no strings or URLs containing comment markers. */
const css = sheet
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .split("\n").map((l) => l.trim()).filter(Boolean).join("\n")
  .replace(/\s*([{};,>])\s*/g, "$1")
  .replace(/;}/g, "}");

/** The script without whole-line comments and indentation (it has no template literals spanning lines). */
const js = readFileSync(here("main.js"), "utf8")
  .split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("//")).join("\n");

// Suisse Intl's three subsets, which the page preloads and its sheet names.
const suisse = ["suisse-intl-medium", "suisse-intl-regular", "suisse-intl-book"];
const missing = suisse.filter((f) => !existsSync(here(`assets/fonts/${f}.woff2`)));
if (missing.length) throw new Error(`website/assets/fonts: missing ${missing.join(", ")}`);

let html = readFileSync(here("index.html"), "utf8")
  .replace(/<!--(?!\[)[\s\S]*?-->/g, "")
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>${css}</style>`)
  .replace('<script src="main.js" defer></script>', () => `<script>${js}</script>`)
  .split("\n").map((l) => l.trim()).filter(Boolean).join("\n");
if (html.includes('href="styles.css"') || html.includes('src="main.js"')) throw new Error("index.html: stylesheet or script tag not found");

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
writeFileSync(out + "index.html", html);
cpSync(here("assets"), out + "assets", { recursive: true });
cpSync(here("en"), out + "en", { recursive: true });
// Cloudflare / Netlify style headers: the font and icons are named for good; the page is asked for each time.
writeFileSync(out + "_headers", [
  "/assets/fonts/*", "  Cache-Control: public, max-age=31536000, immutable",
  "/assets/*", "  Cache-Control: public, max-age=86400",
  "/*", "  X-Content-Type-Options: nosniff", "",
].join("\n"));

const kb = (n) => (n / 1024).toFixed(1) + " KB";
const page = readFileSync(out + "index.html");
console.log(`dist/website/index.html  ${kb(page.length)}  (gzip ${kb(gzipSync(page).length)})`);
for (const f of suisse) console.log(`${f.padEnd(25)}${kb(statSync(out + `assets/fonts/${f}.woff2`).size)}`);
