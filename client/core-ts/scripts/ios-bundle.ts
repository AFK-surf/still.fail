// An ES2020 bundle for the system JavaScriptCore, with all dependencies included.
import { build } from "esbuild";
const [out] = process.argv.slice(2);
if (!out) throw new Error("usage: ios-bundle.ts <out.js>");
await build({
  entryPoints: [new URL("../src/hosts/ios.ts", import.meta.url).pathname],
  bundle: true, format: "iife", platform: "neutral", mainFields: ["module", "main"],
  target: "es2020", minify: true, legalComments: "none", outfile: out,
});
