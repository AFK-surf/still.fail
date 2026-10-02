// chats.ts as one script for the Hermes CLI, which has no host to read a file from: the catalog and the input put
// in as values, then the code, then a run that prints the timing and, after it, the output.
// node build-hermes.mjs <input.json> <runs> <out.js>
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const [, , input, runs, out] = process.argv;
const here = new URL(".", import.meta.url).pathname;
const dir = `${here}../../../client/i18n/catalog/zh`;
const catalog = Object.assign({}, ...readdirSync(dir).filter((f) => f.endsWith(".json")).sort().map((f) => JSON.parse(readFileSync(`${dir}/${f}`, "utf8"))));
const code = stripTypeScriptTypes(readFileSync(`${here}chats.ts`, "utf8"));
writeFileSync(out, `var CATALOG = ${JSON.stringify(catalog)};
var INPUT = ${readFileSync(input, "utf8")};
var host = { now: function () { return typeof performance !== "undefined" ? performance.now() : Date.now(); }, log: print, emit: function () {}, save: function () {} };
${code}
var result = bench(INPUT, ${Number(runs)});
print(JSON.stringify({ engine: "hermes", rows: result.rows, first: result.first, median: result.median }));
print(result.text);
`);
