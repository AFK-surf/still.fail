import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

// Three builds of one client. Default: served by a station under /admin; `pnpm dev:web`
// proxies the API to a local ember. --mode cloud: ember cloud's web app at /, into
// dist/cloud-app, which the Worker serves as static assets. --mode cloud-admin: the
// admin's console (admin/index.html), at / on its own host, into dist/cloud-app/admin-app
// next to it; the Worker serves it on that host only.
export default defineConfig(({ mode }) => {
  const consoleBuild = mode === "cloud-admin";
  return {
    root: here(consoleBuild ? "admin" : "."),
    publicDir: here("public"),
    base: mode === "cloud" || consoleBuild ? "/" : "/admin/",
    plugins: [react()],
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
