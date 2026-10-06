// The emitted declarations name sibling modules as `./x.ts` (as the sources do): rewritten to `./x.js`, which every
// consumer's resolution finds next to its `.d.ts`.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path);
    else if (entry.name.endsWith(".d.ts")) writeFileSync(path, readFileSync(path, "utf8").replace(/(from\s+["']\.{1,2}\/[^"']+)\.ts(["'])/g, "$1.js$2"));
  }
}
walk(new URL("../dist", import.meta.url).pathname);
