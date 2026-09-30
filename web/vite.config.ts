import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
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

// Two builds of one client. Default (or --mode cloud): ember cloud's web app at /, into dist/cloud-web, the static
// Worker ember-web's assets (the desktop app carries it too); `pnpm dev:web` serves it. --mode cloud-admin: the admin's
// console (admin/index.html), at / on its own host, into dist/cloud-admin (ember-admin's). A station serves no page.
export default defineConfig(({ mode }) => {
  const consoleBuild = mode === "cloud-admin";
  // The admin's console reports nothing.
  const posthog = consoleBuild ? null : posthogKey();
  return {
    root: here(consoleBuild ? "admin" : "."),
    publicDir: here("public"),
    base: "/",
    plugins: [react(), vanillaExtractPlugin()],
    define: {
      __POSTHOG__: JSON.stringify(posthog),
      // When this build was made: the core's worker of a newer build takes over from an older one (src/core/worker.ts).
      __BUILT_AT__: JSON.stringify(Date.now()),
      // Which build it is, as the app a message was sent from (src/api.ts).
      __BUILD__: JSON.stringify(buildNumber()),
      // Where a station's web services are shown (cloud/src/preview.ts); the dev rig gives its own.
      __PREVIEW_ORIGIN__: JSON.stringify(process.env.STILLFAIL_PREVIEW_ORIGIN ?? process.env.EMBER_PREVIEW_ORIGIN ?? "https://preview.still.fail"),
    },
    // The core's worker (src/core/worker.ts) is a module worker that loads its wasm.
    worker: { format: "es" },
    build: {
      outDir: here(consoleBuild ? "../dist/cloud-admin" : "../dist/cloud-web"),
      emptyOutDir: true,
      target: "es2022",
      rollupOptions: {
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
