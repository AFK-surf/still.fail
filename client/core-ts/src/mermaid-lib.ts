// mermaid from its package, loaded as it is first wanted (a browser's worker, Node): mermaid.ts.
// deno-lint-ignore no-explicit-any
export const loadMermaid = async (): Promise<any> => (await import("mermaid")).default;
