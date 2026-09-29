import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

// The official site (site/index.html → src/site), with the web app itself in it on made-up data (src/demo), into
// dist/site; `pnpm build:site` also builds the page to HTML (web/site-prerender.mjs).
// No wasm core: its generated files are stood in for, so this builds without client/wasm/build.sh.
export default defineConfig({
  root: here("../site"),
  publicDir: here("public"),
  base: "/",
  plugins: [react(), vanillaExtractPlugin()],
  define: {
    __POSTHOG__: "null",
    __BUILT_AT__: JSON.stringify(Date.now()),
    __PREVIEW_ORIGIN__: JSON.stringify("https://preview.ember.3720.org"),
  },
  resolve: {
    alias: [
      { find: /^\.\/pkg\/built\.js$/, replacement: here("src/demo/stubs/built.js") },
      { find: /^\.\/pkg\/ember_core_wasm\.js$/, replacement: here("src/demo/stubs/ember_core_wasm.js") },
    ],
  },
  server: {
    fs: { allow: [here("..")] },
  },
  // The page built to HTML (web/site-prerender.mjs) runs the app's code in Node: bundled whole, its CSS imports and all.
  ssr: { noExternal: true },
  worker: { format: "es" },
  build: {
    outDir: here("../dist/site"),
    emptyOutDir: true,
    target: "es2022",
  },
});
