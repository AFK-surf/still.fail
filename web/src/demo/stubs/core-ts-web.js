// The demo has no core (vite.demo.config.ts): the worker that would start it is never started.
export async function startWeb() { throw new Error("no core in the demo"); }
