import react from "@vitejs/plugin-react";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

/**
 * PostHog's project key (docs/telemetry.md), from the file $EMBER_POSTHOG
 * names ({host, key}; ~/ember-deploy/posthog.json on studio), with this
 * build's commit as the release. Without it the build has no analytics.
 */
function posthogKey(): { host: string; key: string; release: string } | null {
  const path = process.env.EMBER_POSTHOG;
  if (!path) return null;
  const { host, key } = JSON.parse(readFileSync(path, "utf8")) as { host: string; key: string };
  let release = "unknown";
  try {
    release = execFileSync("git", ["rev-parse", "--short=12", "HEAD"], { cwd: here("."), encoding: "utf8" }).trim();
  } catch { /* not a checkout */ }
  return { host, key, release };
}

/** The station's own error reports (src/telemetry.ts) use the same key: it goes next to the page it came with. */
function stationKeyFile(posthog: { host: string; key: string; release: string }): Plugin {
  return {
    name: "ember-posthog-key",
    generateBundle() {
      this.emitFile({ type: "asset", fileName: "posthog.json", source: `${JSON.stringify(posthog)}\n` });
    },
  };
}

// Three builds of one client. Default: served by a station under /admin; `pnpm dev:web`
// proxies the API to a local ember. --mode cloud: ember cloud's web app at /, into
// dist/cloud-app, which the Worker serves as static assets. --mode cloud-admin: the
// admin's console (admin/index.html), at / on its own host, into dist/cloud-app/admin-app
// next to it; the Worker serves it on that host only.
export default defineConfig(({ mode }) => {
  const consoleBuild = mode === "cloud-admin";
  // The admin's console reports nothing.
  const posthog = consoleBuild ? null : posthogKey();
  return {
    root: here(consoleBuild ? "admin" : "."),
    publicDir: here("public"),
    base: mode === "cloud" || consoleBuild ? "/" : "/admin/",
    plugins: [react(), ...(posthog && mode !== "cloud" ? [stationKeyFile(posthog)] : [])],
    define: {
      __POSTHOG__: JSON.stringify(posthog),
      // When this build was made: the core's worker of a newer build takes over from an older one (src/core/worker.ts).
      __BUILT_AT__: JSON.stringify(Date.now()),
      // Where a station's web services are shown (cloud/src/preview.ts); the dev rig gives its own.
      __PREVIEW_ORIGIN__: JSON.stringify(process.env.EMBER_PREVIEW_ORIGIN ?? "https://preview.ember.3720.org"),
    },
    // The core's worker (src/core/worker.ts) is a module worker that loads its wasm.
    worker: { format: "es" },
    build: {
      outDir: here(consoleBuild ? "../dist/cloud-app/admin-app" : mode === "cloud" ? "../dist/cloud-app" : "../dist/admin"),
      emptyOutDir: true,
      target: "es2022",
    },
    server: { proxy: { "/admin/api": { target: "http://127.0.0.1:4760", changeOrigin: false } } },
  };
});
