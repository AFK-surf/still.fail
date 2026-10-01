import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { fileURLToPath } from "node:url";
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
    .replaceAll("？still.fail 让", "？youdid.wtf 让")
    .replaceAll("https://still.fail/og-image.png", "https://youdid.wtf/og-image.png")
    .replaceAll('href="/favicon-32.png"', 'href="/favicon-beta-32.png"')
    .replaceAll('href="/apple-touch-icon.png"', 'href="/apple-touch-icon-beta.png"'),
};

// The official site (site/index.html → src/site), with the web app itself in it on made-up data (src/demo), into
// dist/site; `pnpm build:site` also builds the page to HTML (web/site-prerender.mjs).
// No wasm core: its generated files are stood in for, so this builds without client/wasm/build.sh.
export default defineConfig({
  root: here("../site"),
  publicDir: here("public"),
  base: "/",
  plugins: [react(), vanillaExtractPlugin(), ...(beta ? [betaHead] : [])],
  define: {
    __SITE_BETA__: JSON.stringify(beta),
    __POSTHOG__: "null",
    __BUILT_AT__: JSON.stringify(Date.now()),
    __PREVIEW_ORIGIN__: JSON.stringify("https://preview.still.fail"),
  },
  resolve: {
    alias: [
      { find: /^\.\/pkg\/built\.js$/, replacement: here("src/demo/stubs/built.js") },
      { find: /^\.\/pkg\/stillfail_core_wasm\.js$/, replacement: here("src/demo/stubs/stillfail_core_wasm.js") },
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
  },
});
