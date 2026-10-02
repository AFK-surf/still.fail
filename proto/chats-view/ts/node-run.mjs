// The built script (build.mjs) on Node's V8: node node-run.mjs <chats.js> <input.json> <runs> [output.json]
import { readFileSync, writeFileSync } from "node:fs";
import vm from "node:vm";

const [, , script, input, runs, output] = process.argv;
const started = performance.now();
globalThis.host = { now: () => performance.now() - started, log: console.log, emit() {}, save() {} };
vm.runInThisContext(readFileSync(script, "utf8"));
const { text, ...result } = globalThis.bench(JSON.parse(readFileSync(input, "utf8")), Number(runs));
if (output) writeFileSync(output, text);
console.log(JSON.stringify({ engine: "v8", ...result }));
