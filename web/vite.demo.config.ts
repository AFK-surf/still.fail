import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { uiAlias } from "./ui/alias.ts";
import { defineConfig, type Plugin } from "vite";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

// STILLFAIL_SITE=beta (`pnpm build:site-beta`): the site of the test channel, youdid.wtf (into dist/site-beta): the
// same page, named youdid.wtf, its downloads the beta apps' (src/site/Site.tsx).
const beta = process.env.STILLFAIL_SITE === "beta";
/** The page's head, named youdid.wtf for the test channel's site, its icons the beta apps' face. */
const betaHead: Plugin = {
  name: "stillfail-site-beta",
  transformIndexHtml: (html) => html
    .replaceAll("<title>still.fail", "<title>youdid.wtf")
    .replaceAll('content="still.fail', 'content="youdid.wtf')
    .replaceAll("https://still.fail/og-image", "https://youdid.wtf/og-image")
    .replaceAll('href="/favicon-32.png"', 'href="/favicon-beta-32.png"')
    .replaceAll('href="/apple-touch-icon.png"', 'href="/apple-touch-icon-beta.png"'),
};

/**
 * How long a browser keeps the site's files (Cloudflare's static assets read `_headers`; without it each is asked for
 * again on every visit): those under assets/ are named by what is in them, so for good; the pages and the files kept
 * under their own names (web/public) are asked for each time, as before.
 */
const keptForGood: Plugin = {
  name: "stillfail-site-kept",
  apply: (_, env) => !env.isSsrBuild,
  generateBundle() {
    this.emitFile({ type: "asset", fileName: "_headers", source: "/assets/*\n  Cache-Control: public, max-age=31536000, immutable\n" });
  },
};

/**
 * The core's formula typesetter (MathJax: a tenth of the demo's script, run as it loads) stood in for: the demo's
 * made-up chats have no formulas, and one a visitor writes in it stays readable as its source, as one MathJax refuses.
 */
const noFormulas: Plugin = {
  name: "stillfail-site-no-formulas",
  enforce: "pre",
  resolveId: (source, importer) => source === "./math.ts" && importer?.endsWith("/client/core-ts/src/markdown.ts") ? here("src/demo/stubs/math.js") : null,
};

/**
 * The last release whose notes are in the repository (docs/releases/<0.1.n>.md, written as each stable release goes
 * out), for the site to say what it brought (src/site/Site.tsx Shipped): its number, its day, how many of its lines are
 * new, better and fixed, and the first few new things (better ones where none are new), each only up to its first pause.
 */
function lastRelease() {
  const dir = here("../docs/releases");
  const n = (f: string) => Number(f.replace(/^0\.1\.|\.md$/g, ""));
  const file = readdirSync(dir).filter((f) => /^0\.1\.\d+\.md$/.test(f)).sort((a, b) => n(b) - n(a))[0];
  if (!file) return null;
  const text = readFileSync(`${dir}/${file}`, "utf8");
  const lines = text.split("\n").filter((l) => l.startsWith("- ")).map((l) => l.slice(2));
  const of = (kind: string) => lines.filter((l) => l.startsWith(`${kind}：`)).map((l) => l.slice(kind.length + 1));
  const fresh = of("新功能"), better = of("改进"), fixed = of("修复");
  return {
    version: `0.1.${n(file)}`,
    date: /^date: (\S+)/m.exec(text)?.[1] ?? "",
    counts: { fresh: fresh.length, better: better.length, fixed: fixed.length },
    lines: (fresh.length ? fresh : better).slice(0, 3).map((l) => l.split(/[，；：]/)[0]!),
  };
}

// The official site (site/index.html → src/site), with the web app itself in it on made-up data (src/demo), into
// dist/site; `pnpm build:site` also builds the page to HTML (web/site-prerender.mjs).
// No core: the worker's modules are stood in for, so this builds without client/iroh-wasm/build.sh.
export default defineConfig({
  root: here("../site"),
  publicDir: here("public"),
  base: "/",
  plugins: [react(), vanillaExtractPlugin(), keptForGood, noFormulas, ...(beta ? [betaHead] : [])],
  define: {
    __SITE_BETA__: JSON.stringify(beta),
    __SITE_RELEASE__: JSON.stringify(lastRelease()),
    __POSTHOG__: "null",
    __BUILT_AT__: JSON.stringify(Date.now()),
    __PREVIEW_ORIGIN__: JSON.stringify("https://preview.still.fail"),
  },
  resolve: {
    alias: [
      { find: /^\.\/iroh-pkg\/built\.js$/, replacement: here("src/demo/stubs/built.js") },
      { find: /^\.\/iroh-pkg\/stillfail_iroh_wasm\.js$/, replacement: here("src/demo/stubs/stillfail_iroh_wasm.js") },
      uiAlias,
      { find: "@stillfail/core-ts/web", replacement: here("src/demo/stubs/core-ts-web.js") },
      { find: "@sqlite.org/sqlite-wasm", replacement: here("src/demo/stubs/sqlite-wasm.js") },
    ],
  },
  server: {
    fs: { allow: [here("..")] },
  },
  // The page built to HTML (web/site-prerender.mjs) runs the app's code in Node: bundled whole, its CSS imports and all.
  ssr: { noExternal: true },
  worker: { format: "es" },
  build: {
    outDir: here(beta ? "../dist/site-beta" : "../dist/site"),
    emptyOutDir: true,
    target: "es2022",
    // The page (in Chinese, and in English: en/), and the phone beside the computer on it (site/phone.html: the app as
    // wide as a phone).
    rollupOptions: { input: { index: here("../site/index.html"), en: here("../site/en/index.html"), phone: here("../site/phone.html"), phoneEn: here("../site/en/phone.html") } },
    // Every style in one sheet: the demo's script comes after the page's own (src/site/main.tsx), and the frame it was
    // built with (its app as HTML) is drawn with the app's styles before it is here. What the built page draws of it is
    // also put in the page's head, and the sheet itself waits at the end of its body (web/site-prerender.mjs).
    cssCodeSplit: false,
  },
});
