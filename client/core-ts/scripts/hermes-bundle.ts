// The core as one script for the Android app's Hermes (hosts/hermes.ts): bundled by esbuild to ES2020 (class fields
// and private members lowered), its classes then made functions by Babel (Hermes 0.81 has none: its experimental
// ES6 classes crash), block scoping left to Hermes (`-block-scoping`, and the engine's runtime config); then, given
// HERMESC, compiled to bytecode as React Native ships its scripts.
//   node scripts/hermes-bundle.ts <out.js> [<out.hbc>]      (HERMESC: the hermesc of the engine's Hermes)
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { transformSync } from "@babel/core";
import { build } from "esbuild";

const [out, hbc] = process.argv.slice(2);
if (!out) throw new Error("usage: hermes-bundle.ts <out.js> [<out.hbc>]");
const built = await build({
  entryPoints: [new URL("../src/hosts/hermes.ts", import.meta.url).pathname],
  bundle: true,
  format: "iife",
  platform: "neutral",
  mainFields: ["module", "main"],
  target: "es2020",
  minify: true,
  legalComments: "none",
  outfile: out,
  logLevel: "warning",
  metafile: true,
});
// What the app does not carry (apps/android/not-carried.txt: a change to only that runs no Android check) must not be
// in it: a file that is would go unchecked.
const root = new URL("../../../", import.meta.url).pathname;
const notCarried = readFileSync(`${root}apps/android/not-carried.txt`, "utf8").split("\n").filter((line) => line && !line.startsWith("#")).map((line) => new RegExp(line));
const carried = Object.keys(built.metafile.inputs).map((input) => relative(root, resolve(input)));
const wrong = carried.filter((path) => notCarried.some((re) => re.test(path)));
if (wrong.length) throw new Error(`the app carries what apps/android/not-carried.txt says it does not: ${wrong.join(", ")}`);
// Classes as functions (and `extends Error` as Babel's wrapped native super, so `instanceof` still holds).
const lowered = transformSync(readFileSync(out, "utf8"), { babelrc: false, configFile: false, compact: true, plugins: ["@babel/plugin-transform-classes"] });
if (!lowered?.code) throw new Error("babel made nothing");
writeFileSync(out, lowered.code);
if (hbc) {
  const hermesc = process.env.HERMESC;
  if (!hermesc) throw new Error("HERMESC: where the engine's hermesc is");
  execFileSync(hermesc, ["-emit-binary", "-O", "-block-scoping", "-out", hbc, out], { stdio: "inherit" });
}
