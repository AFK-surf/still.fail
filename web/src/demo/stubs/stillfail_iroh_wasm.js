// The demo has no core (vite.demo.config.ts): the worker that would load iroh's wasm is never started.
export default async function init() {}
export function bind() { throw new Error("no core in the demo"); }
