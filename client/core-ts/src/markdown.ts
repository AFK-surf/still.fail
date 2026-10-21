// Markdown read once, here, for every client: an agent's words come to the clients parsed, as a compact tree (`Md`), so
// no client parses a message itself, and the same words are read once however many views and clients show them (a
// cache by the text). GitHub's flavour as the web read it before (micromark, as react-markdown did): tables,
// strikethrough, task lists; a bare web address is linked where a reader sees it end (bareLinks.ts), not at the next
// space as GFM's own finding does, and `www.…` and e-mail addresses stay text.
//
// The tree (the shape of Cue's, clients/packages/core/src/markdown/tree.ts there): a run of words is where it stands in
// the text (`[start, end]`, mdWords.ts), so the words go to the clients once, in the text beside the tree; or the words
// themselves where reading changed them (an escape, an entity). Any other node is `[kind, children?, attributes?]`,
// children told from attributes by being an array whose first item is not a number, attributes only what tells a node
// apart (no defaults). Kinds are HTML's names where it has one:
//   blocks  p · ["h", […], {depth}] · ["pre", {code, lang?, ink?}] (`code` words as a run is; `ink`: its colours,
//           highlight.ts) · quote · ["list", [li…], {ordered?, start?}] · ["li", […], {checked?}] (a tight list's item
//           holds its words, a loose one's its paragraphs) · ["table", [tr…], {align}] · tr · th · td · hr
//   inline  b · i · s · ["code", {content}] (words as a run is) · ["a", […], {href, title?}] · ["img", {src, alt?,
//           title?}] · br
// Raw HTML is left out, as the web left it out. An address is as written: a client keeps what it may open.
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmStrikethroughFromMarkdown } from "mdast-util-gfm-strikethrough";
import { gfmTableFromMarkdown } from "mdast-util-gfm-table";
import { gfmTaskListItemFromMarkdown } from "mdast-util-gfm-task-list-item";
import { gfmStrikethrough } from "micromark-extension-gfm-strikethrough";
import { gfmTable } from "micromark-extension-gfm-table";
import { gfmTaskListItem } from "micromark-extension-gfm-task-list-item";
import { bareLinks } from "./bareLinks.ts";
import { ink } from "./highlight.ts";
import { type MdWords, wordsOf } from "./mdWords.ts";

export type MdNode = MdWords | [kind: string] | [kind: string, children: MdNode[]] | [kind: string, attributes: Record<string, unknown>] | [kind: string, children: MdNode[], attributes: Record<string, unknown>];
export type Md = MdNode[];

// mdast as far as it is read here.
type Node = { type: string; position?: { start: { offset?: number }; end: { offset?: number } }; children?: Node[]; value?: string; depth?: number; lang?: string | null; ordered?: boolean | null; start?: number | null; spread?: boolean | null; checked?: boolean | null; align?: (string | null)[] | null; url?: string; title?: string | null; alt?: string | null; identifier?: string; label?: string | null; referenceType?: string };

/// The tree of `text`: read once while it is kept (the latest texts, up to `KEPT_CHARS` of them).
export function markdown(text: string): Md {
  const hit = kept.get(text);
  if (hit) {
    kept.delete(text);
    kept.set(text, hit);
    return hit;
  }
  const md = parse(text);
  kept.set(text, md);
  keptChars += text.length;
  for (const [old] of kept) {
    if (keptChars <= KEPT_CHARS || kept.size <= 1) break;
    kept.delete(old);
    keptChars -= old.length;
  }
  return md;
}

/// How much text the cache holds its trees for (a tree is about as long as its text): a few long histories' worth.
const KEPT_CHARS = 4_000_000;
const kept = new Map<string, Md>();
let keptChars = 0;

/// Parsed afresh (`markdown` keeps it).
export function parse(text: string): Md {
  const root = fromMarkdown(text, {
    extensions: [gfmStrikethrough(), gfmTable(), gfmTaskListItem()],
    mdastExtensions: [gfmStrikethroughFromMarkdown(), gfmTableFromMarkdown(), gfmTaskListItemFromMarkdown()],
  }) as Node;
  const defs = new Map<string, Node>();
  collect(root, defs);
  return blocks(root.children ?? [], { defs, inLink: false, source: text });
}

type Cx = { defs: Map<string, Node>; inLink: boolean; source: string };

/// `value` as a run of the text where the node read it from has it as it is, else the words themselves: the node whole
/// (words), or what is inside its marks (code: after a fence's first line, after inline code's backticks).
function run(value: string, n: Node, cx: Cx): MdWords {
  const from = n.position?.start.offset;
  const to = n.position?.end.offset;
  if (value === "" || from === undefined || to === undefined) return value;
  const source = cx.source;
  if (n.type === "text") return to - from === value.length && source.startsWith(value, from) ? [from, to] : value;
  let inside = from;
  if (n.type === "code" && (source[from] === "`" || source[from] === "~")) inside = source.indexOf("\n", from) + 1 || to;
  else if (n.type === "inlineCode") while (source[inside] === "`") inside++;
  const at = source.indexOf(value, inside);
  return at >= 0 && at + value.length <= to ? [at, at + value.length] : value;
}

function collect(node: Node, defs: Map<string, Node>): void {
  if (node.type === "definition" && node.identifier && !defs.has(normal(node.identifier))) defs.set(normal(node.identifier), node);
  for (const child of node.children ?? []) collect(child, defs);
}

const normal = (id: string) => id.replace(/[\t\n\r ]+/g, " ").trim().toLowerCase();

function blocks(nodes: Node[], cx: Cx): Md {
  return nodes.flatMap((n) => block(n, cx));
}

function block(n: Node, cx: Cx): MdNode[] {
  switch (n.type) {
    case "paragraph": {
      const kids = inlines(n.children ?? [], cx);
      return kids.length ? [["p", kids]] : [];
    }
    case "heading":
      return [["h", inlines(n.children ?? [], cx), { depth: n.depth ?? 1 }]];
    case "code": {
      const value = n.value ?? "";
      const code = run(value, n, cx);
      if (!n.lang) return [["pre", { code }]];
      const colours = ink(value, n.lang);
      return [["pre", colours === null ? { code, lang: n.lang } : { code, lang: n.lang, ink: colours }]];
    }
    case "blockquote":
      return [["quote", blocks(n.children ?? [], cx)]];
    case "list": {
      const attrs: Record<string, unknown> = {};
      if (n.ordered) {
        attrs.ordered = true;
        if (n.start !== null && n.start !== undefined && n.start !== 1) attrs.start = n.start;
      }
      // Tight (no blank line between its items): an item's paragraphs are its words, as HTML draws a tight list.
      const tight = !n.spread && !(n.children ?? []).some((item) => item.spread);
      const items = (n.children ?? []).map((item): MdNode => {
        const inner = tight ? (item.children ?? []).flatMap((c) => (c.type === "paragraph" ? inlines(c.children ?? [], cx) : block(c, cx))) : blocks(item.children ?? [], cx);
        return typeof item.checked === "boolean" ? ["li", inner, { checked: item.checked }] : ["li", inner];
      });
      return [Object.keys(attrs).length ? ["list", items, attrs] : ["list", items]];
    }
    case "table": {
      const rows = (n.children ?? []).map((row, r): MdNode => ["tr", (row.children ?? []).map((cell): MdNode => [r === 0 ? "th" : "td", inlines(cell.children ?? [], cx)])]);
      return [["table", rows, { align: (n.align ?? []).map((a) => a ?? null) }]];
    }
    case "thematicBreak":
      return [["hr"]];
    case "definition":
    case "html":
      return [];
    default:
      // Anything else that holds blocks (footnotes are not read): its blocks.
      return n.children ? blocks(n.children, cx) : n.value ? [["p", [run(n.value, n, cx)]]] : [];
  }
}

function inlines(nodes: Node[], cx: Cx): MdNode[] {
  const out: MdNode[] = [];
  const push = (node: MdNode) => {
    // Neighbouring words as one: two runs that meet, or two of words themselves.
    const last = out.at(-1);
    if (typeof node === "string" && typeof last === "string") out[out.length - 1] = last + node;
    else if (Array.isArray(node) && typeof node[0] === "number" && Array.isArray(last) && typeof last[0] === "number" && last[1] === node[0]) out[out.length - 1] = [last[0], node[1] as number];
    else if (node !== "") out.push(node);
  };
  for (const n of nodes) for (const node of inline(n, cx)) push(node);
  return out;
}

function inline(n: Node, cx: Cx): MdNode[] {
  switch (n.type) {
    case "text": {
      const value = n.value ?? "";
      const whole = run(value, n, cx);
      if (cx.inLink) return [whole];
      // Its bare addresses as links, each part a run of the text where the whole is one.
      let at = 0;
      return bareLinks(value).map((part): MdNode => {
        const words = typeof part === "string" ? part : part.url;
        const piece: MdWords = typeof whole === "string" ? words : [whole[0] + at, whole[0] + at + words.length];
        at += words.length;
        return typeof part === "string" ? piece : ["a", [piece], { href: part.url }];
      });
    }
    case "strong":
      return [["b", inlines(n.children ?? [], cx)]];
    case "emphasis":
      return [["i", inlines(n.children ?? [], cx)]];
    case "delete":
      return [["s", inlines(n.children ?? [], cx)]];
    case "inlineCode":
      return [["code", { content: run(n.value ?? "", n, cx) }]];
    case "break":
      return [["br"]];
    case "link":
      return [link(n.url ?? "", n.title, inlines(n.children ?? [], { ...cx, inLink: true }))];
    case "image":
      return [image(n.url ?? "", n.alt, n.title)];
    case "linkReference":
    case "imageReference": {
      const def = n.identifier ? cx.defs.get(normal(n.identifier)) : undefined;
      if (!def) return [run(`${n.type === "imageReference" ? "!" : ""}[${n.label ?? n.alt ?? ""}]${n.referenceType === "full" ? `[${n.label ?? ""}]` : ""}`, n, cx)];
      return n.type === "imageReference" ? [image(def.url ?? "", n.alt, def.title)] : [link(def.url ?? "", def.title, inlines(n.children ?? [], { ...cx, inLink: true }))];
    }
    case "html":
      return [];
    default:
      return n.children ? inlines(n.children, cx) : n.value ? [run(n.value, n, cx)] : [];
  }
}

function link(href: string, title: string | null | undefined, children: MdNode[]): MdNode {
  return ["a", children, title ? { href, title } : { href }];
}

function image(src: string, alt: string | null | undefined, title: string | null | undefined): MdNode {
  const attrs: Record<string, unknown> = { src };
  if (alt) attrs.alt = alt;
  if (title) attrs.title = title;
  return ["img", attrs];
}

/// Its words as read from `source` (the text it was read from), without the marks (what a quote of it carries, what a
/// search finds).
export function plainOf(md: Md, source: string): string {
  const words = (node: MdNode): string => {
    if (typeof node === "string" || typeof node[0] === "number") return wordsOf(node, source);
    const [kind, first, second] = node as [string, unknown, unknown];
    const attrs = ((Array.isArray(first) ? second : first) ?? {}) as Record<string, unknown>;
    if (kind === "pre") return wordsOf(attrs.code, source);
    if (kind === "code") return wordsOf(attrs.content, source);
    if (kind === "img") return String(attrs.alt ?? "");
    if (kind === "br") return "\n";
    return Array.isArray(first) ? (first as MdNode[]).map(words).join("") : "";
  };
  return md.map(words).join("\n\n");
}
