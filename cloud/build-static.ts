// Writes the preview host's files (src/preview.ts) to dist/cloud-preview, for the static Worker ember-preview, with
// the page marking (web/src/annotate/frame.ts) bundled into one script.
//   node cloud/build-static.ts
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { build } from "vite";
import { previewFiles } from "./src/preview.ts";

const root = join(import.meta.dirname, "..");
const bundled = await build({
  configFile: false, logLevel: "warn",
  build: { write: false, minify: true, lib: { entry: join(root, "web/src/annotate/frame.ts"), formats: ["iife"], name: "stillfailAnnotateBundle" } },
});
const annotate = (Array.isArray(bundled) ? bundled[0]! : bundled as { output: { type: string; code?: string }[] }).output.find((o) => o.type === "chunk")!.code!;
const out = join(root, "dist", "cloud-preview");
const files = previewFiles(annotate);
for (const [path, text] of Object.entries(files)) {
  mkdirSync(dirname(join(out, path)), { recursive: true });
  writeFileSync(join(out, path), text);
}
console.log(`preview host: ${Object.keys(files).length} files in ${out}`);
