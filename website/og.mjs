// The share cards, assets/og/<code>.png (another site's in og/<site>/): each site's built page (build.mjs --site) at
// 1200 × 630 in Chrome, its hero alone on the brand's orange, the bar but the wordmark hidden, no buttons. Take them
// again when the hero changes. Needs playwright-core (the repository's) and a Chrome: CHROME=<its executable>, else Playwright's own.
//   node website/og.mjs [site…]   (default: every site)
import { createServer } from "node:http";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { SITES, TEMPLATE_SITE, loadConfig } from "./build.mjs";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));

const CARD = `
html, body, .hero, .nav, .nav .w { background: #EF6334 !important; }
body > *:not(.nav):not(main), main > *:not(.hero), footer { display: none !important; }
.nav { position: absolute !important; top: 40px !important; left: 0; right: 0; border: 0 !important; box-shadow: none !important; backdrop-filter: none !important; }
.nav::before, .nav::after, .w::before, .w::after, .hero::before, .hero::after, main::before, main::after, body::before, body::after { display: none !important; }
.nav .w { padding-left: 54px !important; max-width: none !important; border: 0 !important; }
.nav-list, .nav-tools, .nav-scrim, .actions, .fpause { display: none !important; }
.brand .wordmark { font-size: 28px !important; color: #1C1B1A !important; }
.brand img { width: 36px !important; height: 36px !important; }
.hero { display: block !important; height: 630px; overflow: hidden; border: 0 !important; --f-eye: 255 255 255 !important; --f-cheek: 248 190 168 !important; --f-you: 28 27 26 !important; }
.hero > .w { padding: 168px 50px 48px !important; max-width: none !important; border: 0 !important; }
.hero-top { grid-template-columns: 1fr !important; gap: 34px !important; }
.hero h1 { font-family: "Suisse Intl", system-ui, sans-serif !important; font-size: 92px !important; font-weight: 500 !important; letter-spacing: -0.02em !important; line-height: 1 !important; color: #1C1B1A !important; max-width: none !important; }
.hero-body { padding-top: 0 !important; }
.hero .lead { font-size: 19px !important; line-height: 1.5 !important; color: #3A2A24 !important; max-width: 28em !important; }
.hero .lead b { color: #1C1B1A !important; }`;

const TYPES = { ".html": "text/html", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2", ".js": "text/javascript" };
const sites = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(SITES);
const cfg = loadConfig();
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
const out = mkdtempSync(join(tmpdir(), "website-og-"));
try {
  for (const site of sites) {
    const root = join(out, site);
    execFileSync(process.execPath, [here("build.mjs"), "--site", site, "--out", root], { stdio: "ignore" });
    // The page with the card's sheet in its head, so the field is drawn in the card's colours from the start.
    const server = createServer((q, r) => {
      let f = join(root, decodeURIComponent(q.url.split("?")[0]));
      if (existsSync(f) && statSync(f).isDirectory()) f = join(f, "index.html");
      if (!existsSync(f)) { r.writeHead(404); r.end(); return; }
      r.writeHead(200, { "content-type": TYPES[extname(f)] ?? "application/octet-stream" });
      r.end(f.endsWith(".html") ? readFileSync(f, "utf8").replace("</head>", `<style>${CARD}</style></head>`) : readFileSync(f));
    }).listen(0, "127.0.0.1");
    await new Promise((ok) => server.on("listening", ok));
    const dir = site === TEMPLATE_SITE ? "assets/og" : `assets/og/${site}`;
    mkdirSync(here(dir), { recursive: true });
    for (const loc of cfg.locales) {
      const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, reducedMotion: "reduce" });
      await page.goto(`http://127.0.0.1:${server.address().port}${loc.prefix}`, { waitUntil: "networkidle" });
      await page.evaluate(() => document.fonts.ready);
      // (the words' and the field's fade in, 300 ms under reduced motion)
      await page.waitForFunction(() => document.querySelector(".field[data-drawn]"));
      await page.waitForTimeout(600);
      await page.screenshot({ path: here(`${dir}/${loc.code}.png`) });
      await page.close();
      console.log(`${dir}/${loc.code}.png`);
    }
    server.close();
  }
} finally {
  await browser.close();
  rmSync(out, { recursive: true, force: true });
}
