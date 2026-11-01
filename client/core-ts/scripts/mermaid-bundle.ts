// mermaid as the app carries it (apps/mbui/src/sfbase/mermaid_lib.mbt): one script that sets globalThis.mermaid, made
// to run in Hermes as the core is (esbuild to ES2020, async functions as generators, Babel's class transform: Hermes
// 0.81 has neither), and in a page as well. Not in the core's bundle: the app gives it to the core the first time a
// chart is drawn (`mermaid.load`, src/mermaid.ts), and a chart the core will not draw is drawn by it in a page. Its
// version is the core's (package.json). Two files of the app's: mermaid_lib.mbt the script (a page's), mermaid_hbc.mbt
// it as the Hermes bytecode the core runs (the engine's: hermesc of React Native 0.81.4, as the core's own is: given as
// HERMESC). Run after mermaid or Hermes changes: apps/mbui/scripts/core.sh mermaid-lib
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { transformSync } from "@babel/core";
import { build } from "esbuild";

const version = JSON.parse(readFileSync(new URL("../node_modules/mermaid/package.json", import.meta.url), "utf8")).version as string;
const built = await build({
  stdin: { contents: 'import mermaid from "mermaid";\nglobalThis.mermaid = mermaid;\n', resolveDir: new URL("..", import.meta.url).pathname },
  bundle: true,
  format: "iife",
  platform: "neutral",
  mainFields: ["module", "main"],
  target: "es2020",
  supported: { "async-await": false, "async-generator": false },
  minify: true,
  legalComments: "none",
  write: false,
  logLevel: "warning",
});
const lowered = transformSync(built.outputFiles[0]!.text, { babelrc: false, configFile: false, compact: true, plugins: ["@babel/plugin-transform-classes"] });
if (!lowered?.code) throw new Error("babel made nothing");
const hermesc = process.env.HERMESC;
if (!hermesc) throw new Error("HERMESC: where the engine's hermesc is");
const dir = mkdtempSync(join(tmpdir(), "mermaid-"));
writeFileSync(join(dir, "mermaid.js"), lowered.code);
execFileSync(hermesc, ["-emit-binary", "-O", "-block-scoping", "-out", join(dir, "mermaid.hbc"), join(dir, "mermaid.js")], { stdio: "pipe", maxBuffer: 1 << 30 }); // (its warnings quote mermaid's lines: not shown)
const hbc = readFileSync(join(dir, "mermaid.hbc"));
// (`--hbc <file>`: the bytecode as it is as well, for core.sh mermaid-smoke)
const raw = process.argv.indexOf("--hbc");
if (raw >= 0) writeFileSync(process.argv[raw + 1]!, hbc);

/// `bytes` gzipped, as a MoonBit Bytes literal (printable ASCII as it is, all else, and `"` and `\`, as \xNN).
function literal(bytes: Uint8Array): { text: string; size: number } {
  const gz = gzipSync(bytes, { level: 9 });
  let text = "";
  for (const b of gz) text += b >= 0x20 && b < 0x7f && b !== 0x22 && b !== 0x5c ? String.fromCharCode(b) : `\\x${b.toString(16).padStart(2, "0")}`;
  return { text, size: gz.length };
}
const head = (what: string) =>
  `// mermaid ${version} as the core's package.json has it, ${what}, gzipped: made by client/core-ts/scripts/mermaid-bundle.ts\n` +
  `// (do not edit: run it again for another version of mermaid or of Hermes). MIT License.\n\n`;
const js = literal(Buffer.from(lowered.code, "utf8"));
writeFileSync(
  new URL("../../../apps/mbui/src/sfbase/mermaid_lib.mbt", import.meta.url),
  head("one script setting globalThis.mermaid, as a page runs it (a chart the core will not draw: viz_page.mbt)") +
    `///|\n// kept across runs: a file's bytes, never written\nlet mermaid_gz : Bytes = b"${js.text}"\n`,
);
const bc = literal(hbc);
writeFileSync(
  new URL("../../../apps/mbui/src/sfbase/mermaid_hbc.mbt", import.meta.url),
  head("that script as the Hermes bytecode the core is given as a chart is first drawn (viz_mermaid.mbt)") +
    `///|\n// kept across runs: a file's bytes, never written\nlet mermaid_hbc_gz : Bytes = b"${bc.text}"\n`,
);
console.log(`mermaid ${version}: ${lowered.code.length} bytes of script (${js.size} gzipped), ${hbc.length} of bytecode (${bc.size} gzipped)`);
