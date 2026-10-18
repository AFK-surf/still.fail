// Runs before ember's hosts/hermes-globals.ts (core/jsc.ts imports it first): keeps JavaScriptCore's own case
// conversion, which hermes-globals replaces with a Latin-1-only one (Hermes on Android needs that; JSC has ICU).
// deno-lint-ignore no-explicit-any
const g = globalThis as any;
g.__mbui_case = { lower: String.prototype.toLowerCase, upper: String.prototype.toUpperCase };
