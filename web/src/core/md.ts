// An agent's Markdown as the core reads it for every client (client/core-ts/src/markdown.ts, where its kinds are
// listed): a run of words is where it stands in the text it was read from (`[start, end]`) or the words themselves;
// any other node is `[kind, children?, attributes?]`. Prose.tsx's MdView draws it.
export type MdNode = string | [start: number, end: number] | [kind: string] | [kind: string, children: MdNode[]] | [kind: string, attributes: Record<string, unknown>] | [kind: string, children: MdNode[], attributes: Record<string, unknown>];
export type Md = MdNode[];
