// Writes the preview host's files (src/preview.ts) to dist/cloud-preview, for the static Worker ember-preview.
//   node cloud/build-static.ts
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { previewFiles } from "./src/preview.ts";

const out = join(import.meta.dirname, "..", "dist", "cloud-preview");
for (const [path, text] of Object.entries(previewFiles())) {
  mkdirSync(dirname(join(out, path)), { recursive: true });
  writeFileSync(join(out, path), text);
}
console.log(`preview host: ${Object.keys(previewFiles()).length} files in ${out}`);
