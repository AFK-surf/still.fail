// The demo has no core (vite.demo.config.ts): SQLite's WASM build, which only the core's worker loads, is not built in.
export default async function init() { throw new Error("no core in the demo"); }
