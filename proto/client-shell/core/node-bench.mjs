// The same core's work (bench in core.ts) on Node's V8, over chats a QuickJS run saved: what QuickJS costs.
// node node-bench.mjs core.ts chats.json
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";

const [, , core, saved] = process.argv;
const started = performance.now();
globalThis.host = { now: () => performance.now() - started, log: console.log, emit() {}, save() {} };
vm.runInThisContext(stripTypeScriptTypes(readFileSync(core, "utf8")));
const chats = JSON.parse(readFileSync(saved, "utf8")).chats;
console.log(JSON.stringify(globalThis.bench(chats)));
