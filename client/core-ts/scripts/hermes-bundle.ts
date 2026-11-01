// The core as one script for the Android app's Hermes (hosts/hermes.ts): bundled by esbuild to ES2020 (class fields
// and private members lowered), its classes then made functions by Babel (Hermes 0.81 has none: its experimental
// ES6 classes crash), block scoping left to Hermes (`-block-scoping`, and the engine's runtime config); then, given
// HERMESC, compiled to bytecode as React Native ships its scripts.
//   node scripts/hermes-bundle.ts [--entry <file>] <out.js> [<out.hbc>]      (HERMESC: the hermesc of the engine's Hermes)
// `--entry`: an app's own entry, giving its modules to the core (hosts/hermes-start.ts); still.fail's is hosts/hermes.ts.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { transformSync } from "@babel/core";
import { build } from "esbuild";

const args = process.argv.slice(2);
const flag = args.indexOf("--entry");
const entry = flag >= 0 ? resolve(args.splice(flag, 2)[1] ?? "") : fileURLToPath(new URL("../src/hosts/hermes.ts", import.meta.url));
const [out, hbc] = args;
if (!out) throw new Error("usage: hermes-bundle.ts [--entry <file>] <out.js> [<out.hbc>]");
const built = await build({
  entryPoints: [entry],
  bundle: true,
  format: "iife",
  platform: "neutral",
  mainFields: ["module", "main"],
  // (#mermaid-lib's: no mermaid in it, the app gives it: src/mermaid.ts)
  conditions: ["hermes"],
  target: "es2020",
  // Hermes 0.81 has no async functions: as generators (mermaid's, mermaid.ts's)
  supported: { "async-await": false, "async-generator": false },
  // STILLFAIL_CORE_NAMES keeps the core's own names (a profile of it read as written: CoreProfileReceiver.kt).
  minifyWhitespace: true,
  minifySyntax: true,
  minifyIdentifiers: !process.env.STILLFAIL_CORE_NAMES,
  legalComments: "none",
  outfile: out,
  logLevel: "warning",
  metafile: true,
});
// What the app does not carry (scripts/not-carried.txt: a change to only that reaches no app) must not be
// in it: a file that is would go unchecked. (Said of still.fail's app; another app's entry is checked the same.)
// (paths, not URLs' pathnames: on Windows those are /D:/…; and the patterns' slashes, whatever the system's)
const root = fileURLToPath(new URL("../../../", import.meta.url));
const notCarried = readFileSync(resolve(root, "client/core-ts/scripts/not-carried.txt"), "utf8").split(/\r?\n/).filter((line) => line && !line.startsWith("#")).map((line) => new RegExp(line));
const carried = Object.keys(built.metafile.inputs).map((input) => relative(root, resolve(input)).split(sep).join("/"));
const wrong = carried.filter((path) => notCarried.some((re) => re.test(path)));
if (wrong.length) throw new Error(`the app carries what scripts/not-carried.txt says it does not: ${wrong.join(", ")}`);
// Classes as functions (and `extends Error` as Babel's wrapped native super, so `instanceof` still holds).
const lowered = transformSync(readFileSync(out, "utf8"), { babelrc: false, configFile: false, compact: true, plugins: ["@babel/plugin-transform-classes"] });
if (!lowered?.code) throw new Error("babel made nothing");
writeFileSync(out, lowered.code);
if (hbc) {
  const hermesc = process.env.HERMESC;
  if (!hermesc) throw new Error("HERMESC: where the engine's hermesc is");
  execFileSync(hermesc, ["-emit-binary", "-O", "-block-scoping", "-out", hbc, out], { stdio: "inherit" });
}
