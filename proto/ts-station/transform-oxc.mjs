// Each .ts of src/ to .js with oxc-transform (types stripped, no bundling), as a per-file build would: dist/oxc/.
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { transformSync } from "oxc-transform";

const files = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(join(dir, e.name)) : e.name.endsWith(".ts") ? [join(dir, e.name)] : []));
for (const file of files("src")) {
  const out = join("dist/oxc", relative("src", file)).replace(/\.ts$/, ".js");
  const { code, errors } = transformSync(file, readFileSync(file, "utf8"), { typescript: { rewriteImportExtensions: "rewrite" } });
  if (errors.length) throw new Error(`${file}: ${errors[0].message}`);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, code);
}
