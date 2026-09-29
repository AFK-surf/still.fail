// The demo has no wasm core (vite.demo.config.ts): the worker that would load it is never started.
export default async function init() {}
export function start() { throw new Error("no core in the demo"); }
