// Markdown read once, here, for every client: an agent's words come to the clients parsed, as a compact tree (`Md`), so
// no client parses a message itself, and the same words are read once however many views and clients show them (a
// cache by the text). GitHub's flavour as the web read it before (micromark, as react-markdown did), read by
// markdown-it (mdRead.ts: six times as fast in Hermes, the phones' engine): tables, strikethrough, task lists; a bare
// web address is linked where a reader sees it end (bareLinks.ts), not at the next space as GFM's own finding does,
// and `www.…` and e-mail addresses stay text.
//
// The tree (the shape of Cue's, clients/packages/core/src/markdown/tree.ts there): a run of words is where it stands in
// the text (`[start, end]`, mdWords.ts), so the words go to the clients once, in the text beside the tree; or the words
// themselves where reading changed them (an escape, an entity). Any other node is `[kind, children?, attributes?]`,
// children told from attributes by being an array whose first item is not a number, attributes only what tells a node
// apart (no defaults). Kinds are HTML's names where it has one:
//   blocks  p · ["h", […], {depth}] · ["pre", {code, lang?, ink?}] (`code` words as a run is; `ink`: its colours,
//           highlight.ts) · quote · ["list", [li…], {ordered?, start?}] · ["li", […], {checked?}] (a tight list's item
//           holds its words, a loose one's its paragraphs) · ["table", [tr…], {align, md, csv}] (`md`, `csv`: the table
//           to copy, as Markdown and as CSV: tableMarkdown, tableCsv) · tr · th · td · hr
//   inline  b · i · s · ["code", {content, path?, line?, shown?}] (words as a run is; `path` where it names a file, a
//           run too, `line` the line it points at, `shown` a chip's words where they are not its path's: paths.ts) ·
//           ["a", […], {href, title?, path?, line?, shown?}] · ["img", {src, alt?, title?}] · br
// Math uses the existing pre/code nodes with `math: true`: $$ or \[ blocks and \( inline spans. Other clients can still
// show the TeX as code. Escaped dollars and dollars inside code keep Markdown's usual meaning.
// Raw HTML is left out, as the web left it out. An address is as written: a client keeps what it may open.
import { bareLinks } from "./bareLinks.ts";
import { ink } from "./highlight.ts";
import { mathDrawing } from "./math.ts";
import { type MdWords, wordsOf } from "./mdWords.ts";
import { pathAttrs } from "./paths.ts";
import { type Node, read } from "./mdRead.ts";
import { shaped, sharedValue } from "./util.ts";

export type MdNode = MdWords | [kind: string] | [kind: string, children: MdNode[]] | [kind: string, attributes: Record<string, unknown>] | [kind: string, children: MdNode[], attributes: Record<string, unknown>];
export type Md = MdNode[];

/// Where trees are kept past this run (an account's database: `md_kept`), by their text's key (`mdKey`), as JSON.
export type MdStore = { has(key: string): boolean; get(key: string): string | null; put(key: string, json: string): void };

/// How the trees kept are read: another number whenever what `parse` makes of a text changes (a test holds it to the
/// trees of a set of texts: markdown.test.ts), so a tree kept by a core before is read afresh, not shown.
export const MD_READING = 5;

/// A text's key among the trees kept: the reading, its length and two FNV-1a hashes of it (64 bits).
export function mdKey(text: string): string {
  let a = 0x811c9dc5;
  let b = 0x01000193 ^ text.length;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193);
    b = Math.imul(b ^ c, 0x0100019d);
  }
  return `${MD_READING}.${text.length}.${(a >>> 0).toString(36)}.${(b >>> 0).toString(36)}`;
}

/// The tree of `text`: read once while it is kept here (the latest texts, up to `KEPT_CHARS` of them), and, given
/// `store`, once on the device: read from it where it was kept, else kept in it. In Hermes (the phones' engine) a
/// chat's page of agents' Markdown took ~0.3 s to read on a Mac Studio's core, the most of opening the chat
/// (bench/chat-open.ts): a chat opened the first time since the app started read it all again.
export function markdown(text: string, store?: MdStore): Md {
  const hit = kept.get(text);
  if (hit) {
    kept.delete(text);
    kept.set(text, hit);
    return hit.md;
  }
  const key = store ? mdKey(text) : "";
  const stored = store?.get(key) ?? null;
  let md: Md | null = null;
  if (stored !== null) {
    try {
      md = JSON.parse(stored) as Md;
    } catch {
      // Not a tree after all: read afresh, kept again.
    }
  }
  const fresh = md === null;
  if (fresh) readAfresh.chars += text.length;
  md ??= parse(text);
  const json = fresh || store === undefined ? JSON.stringify(md) : stored!;
  if (fresh && store) store.put(key, json);
  // Never changed once made, and shared by whatever shows it (kept here by its words): as it goes out (output.ts) it is
  // not copied, put through its shape or kept again as it was, each time a message holding it does. A chat's page of
  // them, walked three times over as it opened, was most of what the core did to open it (2026-10-31).
  shaped.add(sharedValue(md));
  remember(text, md, text.length + json.length);
  return md;
}

/// How many characters of Markdown were read afresh this run (not kept here or on the device): what a page waited for
/// that had to be read as it opened (store.ts `chat.open`).
export const readAfresh = { chars: 0 };

/// Whether `text`'s tree is read and kept here this run.
export function markdownHere(text: string): boolean {
  return kept.has(text);
}

function remember(text: string, md: Md, cost: number): void {
  kept.set(text, { md, cost });
  keptChars += cost;
  for (const [old, entry] of kept) {
    if (keptChars <= KEPT_CHARS || kept.size <= 1) break;
    kept.delete(old);
    keptChars -= entry.cost;
  }
}

/// Bound the trees as well as their source: a short formula may have many placed glyphs.
const KEPT_CHARS = 4_000_000;
const kept = new Map<string, { md: Md; cost: number }>();
let keptChars = 0;

/// Parsed afresh (`markdown` keeps it).
export function parse(text: string): Md {
  const root = read(text);
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
  if (n.type === "inlineMath" && source[from] === "\\") inside += 2;
  else if (n.type === "math" || (n.type === "code" && (source[from] === "`" || source[from] === "~"))) inside = source.indexOf("\n", from) + 1 || to;
  else if (n.type === "inlineCode") while (source[inside] === "`") inside++;
  else if (n.type === "inlineMath") while (source[inside] === "$") inside++;
  const at = source.indexOf(value, inside);
  return at >= 0 && at + value.length <= to ? [at, at + value.length] : value;
}

function collect(node: Node, defs: Map<string, Node>): void {
  if (node.type === "definition" && node.identifier && !defs.has(normal(node.identifier))) defs.set(normal(node.identifier), node);
  for (const child of node.children ?? []) collect(child, defs);
}

const normal = (id: string) => id.replace(/[\t\n\r ]+/g, " ").trim().toLowerCase();

/// A paragraph's words, a line holding only a link or a picture set apart as a paragraph of its own: written on a
/// line of its own, as a file's or a screen's link is to be shown whole (its card, the file itself), it is so though no
/// blank line sets it apart (the user, 2026-10-30: a video's link with its words on the very next line showed as a
/// link in a sentence). The lines round it stay one paragraph, as Markdown has them.
function lineParagraphs(nodes: Node[]): Node[][] {
  // its lines, a text split where it breaks (each piece where it stands in the text, where the text is as written)
  let line: Node[] = [];
  const lines: Node[][] = [line];
  for (const n of nodes) {
    const value = n.value ?? "";
    if (n.type !== "text" || !value.includes("\n")) {
      line.push(n);
      continue;
    }
    const from = n.position?.start.offset;
    const to = n.position?.end.offset;
    const placed = from !== undefined && to !== undefined && to - from === value.length;
    let at = 0;
    for (const piece of value.split("\n")) {
      if (at > 0) lines.push((line = []));
      if (piece !== "") line.push(placed ? { type: "text", value: piece, position: { start: { offset: from + at }, end: { offset: from + at + piece.length } } } : { type: "text", value: piece });
      at += piece.length + 1;
    }
  }
  const lone = (line: Node[]): boolean => {
    const seen = line.filter((x) => !(x.type === "text" && (x.value ?? "").trim() === ""));
    const [only] = seen;
    return seen.length === 1 && (only?.type === "link" || only?.type === "image");
  };
  if (lines.length < 2 || !lines.some(lone)) return [nodes];
  // the lines between the lone ones together again, their breaks as they were
  const out: Node[][] = [];
  let run: Node[] = [];
  const end = () => {
    if (run.length > 0) out.push(run);
    run = [];
  };
  for (const each of lines) {
    if (lone(each)) {
      end();
      out.push(each.filter((x) => !(x.type === "text" && (x.value ?? "").trim() === "")));
      continue;
    }
    if (run.length > 0) run.push({ type: "text", value: "\n" });
    run.push(...each);
  }
  end();
  return out;
}

function blocks(nodes: Node[], cx: Cx): Md {
  return nodes.flatMap((n) => block(n, cx));
}

function block(n: Node, cx: Cx): MdNode[] {
  switch (n.type) {
    case "paragraph":
      return lineParagraphs(n.children ?? []).flatMap((line) => {
        const kids = inlines(line, cx);
        return kids.length ? [["p", kids] as MdNode] : [];
      });
    case "heading":
      return [["h", inlines(n.children ?? [], cx), { depth: n.depth ?? 1 }]];
    case "inlineMath": // A \[ block uses the same delimiter tokens as inline TeX (mathSyntax.ts).
    case "math":
    case "code": {
      const value = n.type === "inlineMath" ? (n.value ?? "").replace(/^(\r?\n|\r)|(\r?\n|\r)$/g, "") : n.value ?? "";
      const code = run(value, n, cx);
      // Existing code nodes keep TeX readable on clients without a formula renderer.
      if (n.type !== "code") return [["pre", { code, math: true, drawing: mathDrawing(value, true) }]];
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
      const align = (n.align ?? []).map((a) => a ?? null);
      const cells = (n.children ?? []).map((row) => (row.children ?? []).map((cell) => ({ written: cell.value ?? "", words: inlines(cell.children ?? [], cx) })));
      const rows = cells.map((row, r): MdNode => ["tr", row.map((cell): MdNode => [r === 0 ? "th" : "td", cell.words])]);
      const md = tableMarkdown(cells.map((row) => row.map((cell) => cell.written)), align);
      const csv = tableCsv(cells.map((row) => row.map((cell) => cell.words.map((w) => wordsIn(w, cx.source, true)).join(""))));
      return [["table", rows, { align, md, csv }]];
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
    // (one naming a file: its path, a run of the text as its words are, the line it points at, a chip's words: paths.ts)
    case "inlineCode":
      return [["code", { content: run(n.value ?? "", n, cx), ...pathAttrs(n.value ?? "", (path) => run(path, n, cx)) }]];
    case "inlineMath":
      return [["code", { content: run(n.value ?? "", n, cx), math: true, drawing: mathDrawing(n.value ?? "", false) }]];
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

/// A link; one to a file by its path (no scheme: `src/a.ts`, `./notes.md#L3`) says that file as an inline code naming it
/// does (paths.ts).
function link(href: string, title: string | null | undefined, children: MdNode[]): MdNode {
  const file = /^[a-z][\w+.-]*:/i.test(href) ? {} : pathAttrs(decoded(href), (path) => path);
  return ["a", children, { href, ...(title ? { title } : {}), ...file }];
}

const decoded = (s: string): string => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
};

function image(src: string, alt: string | null | undefined, title: string | null | undefined): MdNode {
  const attrs: Record<string, unknown> = { src };
  if (alt) attrs.alt = alt;
  if (title) attrs.title = title;
  return ["img", attrs];
}

/// Its words as read from `source` (the text it was read from), without the marks (what a quote of it carries, what a
/// search finds).
export function plainOf(md: Md, source: string): string {
  return md.map((node) => wordsIn(node, source)).join("\n\n");
}

/// A node's words as read from `source`, without the marks; an image's its words, or (`addressed`) its address where it
/// has none.
function wordsIn(node: MdNode, source: string, addressed = false): string {
  if (typeof node === "string" || typeof node[0] === "number") return wordsOf(node, source);
  const [kind, first, second] = node as [string, unknown, unknown];
  const attrs = ((Array.isArray(first) ? second : first) ?? {}) as Record<string, unknown>;
  if (kind === "pre") return wordsOf(attrs.code, source);
  if (kind === "code") return wordsOf(attrs.content, source);
  if (kind === "img") return String(attrs.alt || (addressed ? attrs.src ?? "" : ""));
  if (kind === "br") return "\n";
  return Array.isArray(first) ? (first as MdNode[]).map((k) => wordsIn(k, source, addressed)).join("") : "";
}

/// A table as GitHub's Markdown writes one, whatever its lines were written in (a quote's, a list's): its cells as
/// written (`rows`, the head first), a bar in one escaped; under the head how each column is aligned.
export function tableMarkdown(rows: string[][], align: (string | null)[]): string {
  const line = (cells: string[]) => `| ${cells.map((c) => c.replace(/\|/g, "\\|")).join(" | ")} |`;
  const rule = align.map((a) => (a === "left" ? ":--" : a === "right" ? "--:" : a === "center" ? ":-:" : "---"));
  const [head = [], ...body] = rows;
  return [line(head), `| ${rule.join(" | ")} |`, ...body.map(line)].join("\n");
}

/// A table's words as CSV (RFC 4180, lines apart by a line's end): a cell in quotes where it holds a comma, a quote or a
/// line's end, a quote in one doubled.
export function tableCsv(rows: string[][]): string {
  const cell = (c: string) => (/[",\r\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c);
  return rows.map((row) => row.map(cell).join(",")).join("\n");
}

/// Its first line of words, without the marks, as plainOf reads them: what a line standing for it shows closed (a
/// history's event). Within a list or a quote, its first item's; a table's head row, its cells apart by a bar; a code
/// block's first line as written.
export function lineOf(md: Md, source: string): string {
  const BLOCKS = ["p", "h", "pre", "quote", "list", "li", "table", "tr", "hr"];
  const block = (node: MdNode) => typeof node !== "string" && typeof node[0] === "string" && BLOCKS.includes(node[0]);
  const kids = (node: MdNode): MdNode[] => (typeof node !== "string" && Array.isArray(node[1]) ? (node[1] as MdNode[]) : []);
  // (words within a block, as a paragraph's: plainOf sets blocks apart)
  const inline = (nodes: MdNode[]) => plainOf([["p", nodes]], source);
  const first = (nodes: MdNode[]): string => {
    for (const node of nodes) {
      const kind = typeof node !== "string" && typeof node[0] === "string" ? node[0] : null;
      // (a tight list's item holds its words; a loose one's, its paragraphs)
      const words =
        kind === "quote" || kind === "list" || (kind === "li" && kids(node).some(block))
          ? first(kids(node))
          : kind === "table"
            ? kids(kids(node)[0] ?? ["tr"]).map((cell) => inline(kids(cell)).trim()).join(" | ")
            : kind === "li"
              ? inline(kids(node))
              : plainOf([node], source);
      const line = words.split("\n").map((l) => l.trim()).find((l) => l !== "");
      if (line !== undefined) return line;
    }
    return "";
  };
  return first(md);
}
