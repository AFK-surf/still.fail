import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { execFileSync } from "node:child_process";
import { readFileSync, renameSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { uiAlias } from "./ui/alias.ts";
import { defineConfig } from "vite";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

/**
 * PostHog's project key (docs/telemetry.md), from the file $STILLFAIL_POSTHOG
 * ($EMBER_POSTHOG before the rename) names ({host, key}; ~/ember-deploy/posthog.json on studio), with this
 * build's commit as the release. Without it the build has no analytics. The station's own copy is written by
 * scripts/posthog-key.ts, the same way.
 */
function posthogKey(): { host: string; key: string; release: string } | null {
  const path = process.env.STILLFAIL_POSTHOG ?? process.env.EMBER_POSTHOG;
  if (!path) return null;
  const { host, key } = JSON.parse(readFileSync(path, "utf8")) as { host: string; key: string };
  let release = "unknown";
  try {
    release = execFileSync("git", ["rev-parse", "--short=12", "HEAD"], { cwd: here("."), encoding: "utf8" }).trim();
  } catch { /* not a checkout */ }
  return { host, key, release };
}

/** This build as the apps number theirs, 0.1.<commits in the history>; null outside a checkout. */
function buildNumber(): string | null {
  try {
    return `0.1.${execFileSync("git", ["rev-list", "--count", "HEAD"], { cwd: here("."), encoding: "utf8" }).trim()}`;
  } catch {
    return null;
  }
}

// Two builds of one client. Default (or --mode cloud): still.fail cloud's web app at /, into dist/cloud-web, the static
// Worker ember-web's assets (the desktop app carries it too); `pnpm dev:web` serves it. --mode cloud-admin: the admin's
// console (admin/index.html), at / on its own host, into dist/cloud-admin (ember-admin's). A station serves no page.
// STILLFAIL_PROFILE=1: a build to measure React's work in (test/perf/renders.mjs), into dist/profile: React's profiling
// build, which times each render, and nothing minified, so what rendered is told by its component's name.
const profiling = process.env.STILLFAIL_PROFILE === "1";

export default defineConfig(({ mode }) => {
  const consoleBuild = mode === "cloud-admin";
  // The admin's console reports nothing.
  const posthog = consoleBuild ? null : posthogKey();
  const build = buildNumber();
  const revision = build ? execFileSync("git", ["rev-parse", "HEAD"], { cwd: here("."), encoding: "utf8" }).trim() : null;
  return {
    root: here(consoleBuild ? "admin" : "."),
    publicDir: here("public"),
    base: "/",
    plugins: [
      react(),
      vanillaExtractPlugin(),
      // The web app's build.json: which build it is, for deploy.py to say what app.still.fail (or the test channel's)
      // has out (the releases bucket's web.json, cloud/src/changelog.ts).
      {
        name: "stillfail-build",
        apply: "build",
        generateBundle() {
          if (!consoleBuild && build) this.emitFile({ type: "asset", fileName: "build.json", source: `${JSON.stringify({ version: build, build: Number(build.split(".")[2]), revision })}\n` });
        },
      },
      // The app's page is the built index.html, what every page of the app's answers with (the Worker's
      // single-page-application fallback): the app drawn by mbui (mbui.html), as every device runs it. The web's own
      // React pages (index.html) become web.html, which src/web.ts serves at the few pages the app has none of yet.
      {
        name: "stillfail-app-page",
        apply: "build",
        writeBundle(options) {
          if (consoleBuild || !options.dir) return;
          renameSync(join(options.dir, "index.html"), join(options.dir, "web.html"));
          renameSync(join(options.dir, "mbui.html"), join(options.dir, "index.html"));
        },
      },
    ],
    define: {
      __POSTHOG__: JSON.stringify(posthog),
      // When this build was made: the core's worker of a newer build takes over from an older one (src/core/worker.ts).
      __BUILT_AT__: JSON.stringify(Date.now()),
      // Which build it is, as the app a message was sent from (src/api.ts).
      __BUILD__: JSON.stringify(build),
      __WEB_REVISION__: JSON.stringify(revision),
      // Where a station's web services are shown (cloud/src/preview.ts); the dev rig gives its own.
      __PREVIEW_ORIGIN__: JSON.stringify(process.env.STILLFAIL_PREVIEW_ORIGIN ?? process.env.EMBER_PREVIEW_ORIGIN ?? "https://preview.still.fail"),
    },
    // The core's worker (src/core/worker.ts) is a module worker: the TypeScript core, SQLite's and iroh's wasm.
    worker: { format: "es" },
    // SQLite's WASM build finds its .wasm beside its module (new URL(…, import.meta.url)): not prebundled in dev.
    optimizeDeps: { exclude: ["@sqlite.org/sqlite-wasm"] },
    resolve: {
      alias: [
        uiAlias,
        { find: "@stillfail/core-ts/web", replacement: here("../client/core-ts/src/hosts/web.ts") },
        ...(profiling ? [{ find: /^react-dom\/client$/, replacement: "react-dom/profiling" }] : []),
      ],
    },
    build: {
      outDir: here(consoleBuild ? "../dist/cloud-admin" : profiling ? "../dist/profile/cloud-web" : "../dist/cloud-web"),
      emptyOutDir: true,
      target: "es2022",
      ...(profiling ? { minify: false } : {}),
      rollupOptions: {
        // still.fail's app drawn by mbui (mbui.html: src/mbui/core.ts) beside the web's own pages, on the same core
        ...(consoleBuild ? {} : { input: { main: here("index.html"), mbui: here("mbui.html") } }),
        output: {
          // Scripts that come in as files (pdf.js's worker, `pdf.worker.min.mjs?url`) keep their .mjs, and a module
          // loaded from a file served as application/octet-stream fails (strict MIME). The dev cloud and older hosts
          // only know .js as JavaScript, so name them .js.
          assetFileNames: (asset) => (asset.names.some((n) => n.endsWith(".mjs")) ? "assets/[name]-[hash].js" : "assets/[name]-[hash][extname]"),
        },
      },
    },
  };
});
