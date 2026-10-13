// An agent's Markdown as the core reads it for every client (client/core-ts/src/markdown.ts, where its kinds are
// listed): text is itself; any other node is `[kind, children?, attributes?]`. Prose.tsx's MdView draws it.
export type MdNode = string | [kind: string] | [kind: string, children: MdNode[]] | [kind: string, attributes: Record<string, unknown>] | [kind: string, children: MdNode[], attributes: Record<string, unknown>];
export type Md = MdNode[];
