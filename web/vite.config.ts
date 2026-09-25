import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// Two builds of one client. Default: served by a station under /admin; `pnpm dev:web`
// proxies the API to a local ember. --mode cloud: ember cloud's web app at /, into
// dist/cloud-app, which the Worker serves as static assets.
export default defineConfig(({ mode }) => ({
  root: fileURLToPath(new URL(".", import.meta.url)),
  base: mode === "cloud" ? "/" : "/admin/",
  plugins: [react()],
  build: {
    outDir: fileURLToPath(new URL(mode === "cloud" ? "../dist/cloud-app" : "../dist/admin", import.meta.url)),
    emptyOutDir: true,
    target: "es2022",
  },
  server: { proxy: { "/admin/api": { target: "http://127.0.0.1:4760", changeOrigin: false } } },
}));
