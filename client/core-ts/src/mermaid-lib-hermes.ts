// mermaid in Hermes: not in the core's script (it would double it, and the time it takes to make), but the one the app
// carries, run here as the app gives it (mermaid.ts provideMermaid: it sets globalThis.mermaid); none till then.
// deno-lint-ignore no-explicit-any
export const loadMermaid = async (): Promise<any> => (globalThis as { mermaid?: unknown }).mermaid;
