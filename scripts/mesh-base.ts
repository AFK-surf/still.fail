// The mesh's base imports nothing of the station's business (station/AGENTS.md, Its shape): the files another program
// is served by (the wire, the door, the endpoint's types and what watches a connection) import, by a relative path,
// only each other and the leaves below; node's own modules and npm's packages aside. A type counts as a value does: a
// file that names the station's credentials, locks or routes even in a type cannot be taken without them.
// Prints each import that is not so, and fails then.
//   node scripts/mesh-base.ts
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/// The base. A file is added once it is so; none is taken out to let an import in.
const BASE = [
  "station/src/mesh/wire.ts",
  "station/src/mesh/door.ts",
  "station/src/mesh/reply-watch.ts",
  "station/src/mesh/native.ts",
  "station/src/mesh/compress.ts",
  "station/src/mesh/storms.ts",
  "station/src/mesh/superseded.ts",
  "station/src/mesh/lan.ts",
  "station/src/mesh/settings.ts",
  "station/src/api/event-log.ts",
];

/// What the base may import besides itself: the station's log and its time, which import only each other. Held to the
/// same rule as the base, so that they stay leaves. This table only shrinks.
const LEAVES = ["station/src/ops/log.ts", "station/src/ops/fibers.ts"];

const allowed = new Set([...BASE, ...LEAVES]);
const wrong: string[] = [];
for (const file of allowed) {
  if (!existsSync(join(root, file))) {
    wrong.push(`${file}: listed in scripts/mesh-base.ts and not there`);
    continue;
  }
  const lines = readFileSync(join(root, file), "utf8").split("\n");
  // (line by line: a statement over several lines has its path on the line that ends it)
  lines.forEach((line, i) => {
    if (/^\s*(\/\/|\*)/.test(line)) return;
    for (const match of line.matchAll(/\bfrom\s*["']([^"']+)["']|\bimport\s*["']([^"']+)["']|\b(?:import|require)\s*\(\s*["']([^"']+)["']/g)) {
      const path = match[1] ?? match[2] ?? match[3] ?? "";
      if (!path.startsWith(".")) continue;
      const to = normalize(join(dirname(file), path));
      if (!allowed.has(to)) wrong.push(`${file}:${i + 1}: imports ${to}`);
    }
    // (a path made as it runs could be any file's)
    if (/\b(import|require)\s*\(\s*[^"'\s)]/.test(line)) wrong.push(`${file}:${i + 1}: imports a path it does not write out`);
  });
}
if (wrong.length > 0) {
  console.log(wrong.join("\n"));
  console.log("(the mesh's base stands without the station's business: give it what it needs as a parameter, or keep what needs the import outside it)");
  process.exit(1);
}
