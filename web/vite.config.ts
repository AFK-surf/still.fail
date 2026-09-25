import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// The admin client is served by ember under /admin; `pnpm dev:web` proxies the API to a local ember.
export default defineConfig({
  root: fileURLToPath(new URL(".", import.meta.url)),
  base: "/admin/",
  plugins: [react()],
  build: { outDir: fileURLToPath(new URL("../dist/admin", import.meta.url)), emptyOutDir: true },
  server: { proxy: { "/admin/api": { target: "http://127.0.0.1:4760", changeOrigin: false } } },
});
