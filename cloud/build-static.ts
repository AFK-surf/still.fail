// Writes the preview host's files (src/preview.ts) to dist/cloud-preview, for the static Worker ember-preview, with
// the page marking (web/src/annotate/frame.ts) bundled into one script; and the share host's (src/share.ts) beside its
// page in dist/cloud-share (built before: `vp build --config web/vite.share.config.ts`), for stillfail-share, for the
// cloud and relays share-hosts.ts says.
//   node cloud/build-static.ts
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { build } from "vite";
import { previewFiles } from "./src/preview.ts";
import { shareFiles } from "./src/share.ts";
import { shareHosts } from "./share-hosts.ts";

const root = join(import.meta.dirname, "..");
const bundled = await build({
  configFile: false, logLevel: "warn",
  build: { write: false, minify: true, lib: { entry: join(root, "web/src/annotate/frame.ts"), formats: ["iife"], name: "stillfailAnnotateBundle" } },
});
const annotate = (Array.isArray(bundled) ? bundled[0]! : bundled as { output: { type: string; code?: string }[] }).output.find((o) => o.type === "chunk")!.code!;

function write(out: string, files: Record<string, string>) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(out, path)), { recursive: true });
    writeFileSync(join(out, path), text);
  }
}

const preview = join(root, "dist", "cloud-preview");
const files = previewFiles(annotate);
write(preview, files);
console.log(`preview host: ${Object.keys(files).length} files in ${preview}`);

const share = join(root, "dist", "cloud-share");
if (!existsSync(join(share, "index.html"))) throw new Error(`${share} has no page: build it first (vp build --config web/vite.share.config.ts)`);
const hosts = shareHosts();
write(share, shareFiles(hosts));
console.log(`share host: its files in ${share}, for ${hosts.cloud} and ${hosts.relays.join(", ")}`);
