import react from "@vitejs/plugin-react";
import { vanillaExtractPlugin } from "@vanilla-extract/vite-plugin";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";
import { shareHosts } from "../cloud/share-hosts.ts";
import { uiAlias } from "./ui/alias.ts";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

// The share host's page (share/index.html → src/share; cloud/src/share.ts says what the host is), into dist/cloud-share,
// where build-static.ts puts the host's other files beside it. It draws messages with the chat's own Markdown and
// visualizations (Prose.tsx, Viz.tsx) and opens files in the chat's own preview (FilePreview.tsx, its files read
// through a FileSource of the page's), and nothing else of the app: no core, no station. What those reach of the app
// that needs one is stood in for (src/share/stand-ins/), by the file it is, as the site's build stands in for the core
// (vite.demo.config.ts). It asks the cloud share-hosts.ts says for the relays, and reads the rest from the station.
const standIns: Record<string, string> = Object.fromEntries(
  ["i18n.ts", "ui.tsx", "Peeks.tsx", "ChatRef.tsx", "api.ts", "draft.ts", "fonts.ts", "station.tsx", "core/react.ts", "annotate/ImageMarks.tsx"]
    .map((name) => [here(`src/${name}`), here(`src/share/stand-ins/${name}`)]),
);
const standIn: Plugin = {
  name: "stillfail-share-stand-ins",
  enforce: "pre",
  async resolveId(source, importer, options) {
    if (!importer || importer.startsWith(here("src/share/stand-ins/"))) return null;
    const resolved = await this.resolve(source, importer, { ...options, skipSelf: true });
    return resolved && standIns[resolved.id] ? standIns[resolved.id] : null;
  },
};

export default defineConfig({
  root: here("share"),
  publicDir: false,
  base: "/",
  plugins: [standIn, react(), vanillaExtractPlugin()],
  define: {
    // The cloud the page asks for the relays (/v1/relays).
    __SHARE_CLOUD__: JSON.stringify(shareHosts().cloud),
  },
  resolve: { alias: [uiAlias] },
  server: {
    fs: { allow: [here("..")] },
  },
  build: {
    outDir: here("../dist/cloud-share"),
    emptyOutDir: true,
    target: "es2022",
  },
});
