// The words of the core's Markdown (`Md`, markdown.ts) for a client that draws it: a run of words is where it stands
// in the text the tree was read from (`[start, end]`, UTF-16 units), so the tree does not carry the words a second
// time beside the text; or the words themselves where reading changed them (an escape, an entity, an indented
// block's lines). Nothing here reads Markdown: a client's page takes this file alone.

/// A run of words in a tree: in its text, from `start` to `end`; or the words themselves.
export type MdWords = string | [start: number, end: number];

/// Whether a node of the tree is a run of words (a string, or `[start, end]`), not a node of a kind.
export const isWords = (node: unknown): node is MdWords => typeof node === "string" || (Array.isArray(node) && typeof node[0] === "number");

/// The words of a run (or of an attribute that holds one: a code block's `code`, inline code's `content`), in `source`,
/// the text the tree was read from.
export function wordsOf(words: unknown, source: string): string {
  if (typeof words === "string") return words;
  if (Array.isArray(words) && typeof words[0] === "number" && typeof words[1] === "number") return source.slice(words[0], words[1]);
  return "";
}
