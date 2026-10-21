// The core's Markdown with its runs of words read out of the text it came from (mdWords.ts), as a client draws it: what
// the tests compare.
import type { Md, MdNode } from "../src/markdown.ts";
import { isWords, wordsOf } from "../src/mdWords.ts";

export function wordsIn(md: Md, source: string): unknown[] {
  const node = (n: MdNode): unknown => {
    if (isWords(n)) return wordsOf(n, source);
    const [kind, first, second] = n as [string, unknown, unknown];
    const attrs = (Array.isArray(first) ? second : first) as Record<string, unknown> | undefined;
    const read = attrs && ("code" in attrs || "content" in attrs)
      ? { ...attrs, ...("code" in attrs ? { code: wordsOf(attrs.code, source) } : {}), ...("content" in attrs ? { content: wordsOf(attrs.content, source) } : {}) }
      : attrs;
    const out: unknown[] = [kind];
    if (Array.isArray(first)) out.push((first as MdNode[]).map(node));
    if (read) out.push(read);
    return out;
  };
  return md.map(node);
}
