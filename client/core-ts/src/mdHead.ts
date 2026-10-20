// The beginning of an agent's words, for a view that shows only their first lines (a history's fold): what is past
// them is neither made nor laid out until a reader unfolds it. Nothing here reads Markdown: a client's page takes this
// file alone (markdown.ts brings the parser).
import type { Md, MdNode } from "./markdown.ts";

// The widest a line is taken to be, in Latin letters (a wide character, CJK, counts two): no narrower than any view
// draws one, so the lines counted here are never more than the lines drawn.
const LINE = 160;

const units = (text: string): number => {
  let n = 0;
  for (let i = 0; i < text.length; i++) n += text.charCodeAt(i) >= 0x2e80 ? 2 : 1;
  return n;
};
/// `text` up to `room` units, never through the middle of a pair.
function sliced(text: string, room: number): string {
  let n = 0;
  let i = 0;
  for (; i < text.length && n < room; i++) n += text.charCodeAt(i) >= 0x2e80 ? 2 : 1;
  const hi = text.charCodeAt(i - 1);
  return text.slice(0, hi >= 0xd800 && hi <= 0xdbff ? i - 1 : i);
}

const kidsOf = (node: Exclude<MdNode, string>): MdNode[] => (Array.isArray(node[1]) ? node[1] : []);
const attrsOf = (node: Exclude<MdNode, string>): Record<string, unknown> | undefined => (Array.isArray(node[1]) ? node[2] : node[1]);
const withKids = (node: Exclude<MdNode, string>, kids: MdNode[]): MdNode => {
  const attrs = attrsOf(node);
  return attrs ? [node[0], kids, attrs] : [node[0], kids];
};
// What holds blocks, each on lines of its own; anything else that has children holds words running on one another.
const BLOCKS = new Set(["quote", "list", "table"]);

type Taken = { node: MdNode; lines: number; cut: boolean };

/// `nodes` while they fill less than `room` lines: blocks one under another, or the words of one block.
function taken(nodes: MdNode[], room: number, inline: boolean, per: number): { kept: MdNode[]; lines: number; cut: boolean } {
  const kept: MdNode[] = [];
  let lines = 0;
  for (const node of nodes) {
    if (lines >= room) return { kept, lines, cut: true };
    const t = inline ? word(node, room - lines, per) : block(node, room - lines, per);
    kept.push(t.node);
    lines += t.lines;
    if (t.cut) return { kept, lines, cut: true };
  }
  return { kept, lines, cut: false };
}
/// A block: at least a line, whatever it holds.
function block(node: MdNode, room: number, per: number): Taken {
  if (typeof node === "string") return word(node, room, per);
  const kind = node[0];
  if (kind === "pre") {
    const a = attrsOf(node) ?? {};
    const code = typeof a.code === "string" ? a.code : "";
    const rows = code.split("\n");
    // A chart is drawn from all of its words or not at all.
    if (rows.length <= room || String(a.lang ?? "").toLowerCase() === "mermaid") return { node, lines: rows.length, cut: false };
    const n = Math.ceil(room);
    return { node: ["pre", { ...a, code: rows.slice(0, n).join("\n") }], lines: n, cut: true };
  }
  // A row of a table is whole or not there.
  if (kind === "tr" || kind === "hr") return { node, lines: kind === "tr" ? 1 : 0, cut: false };
  const kids = kidsOf(node);
  // A list's item holds its words (a tight list) or its blocks (a loose one, or a list within it).
  const blocks = BLOCKS.has(kind) || (kind === "li" && kids.some((k) => typeof k !== "string" && (k[0] === "p" || BLOCKS.has(k[0]) || k[0] === "pre")));
  if (blocks) {
    // Words beside blocks in an item (its own line, then a list within it): each run of them a line.
    const t = taken(kids, room, false, per);
    return { node: t.cut ? withKids(node, t.kept) : node, lines: Math.max(1, t.lines), cut: t.cut };
  }
  const t = taken(kids, room, true, per);
  return { node: t.cut ? withKids(node, t.kept) : node, lines: Math.max(1, Math.ceil(t.lines)), cut: t.cut };
}
/// Words within a block: the part of a line they take, a break a line.
function word(node: MdNode, room: number, per: number): Taken {
  if (typeof node === "string") {
    const n = units(node);
    if (n / per <= room) return { node, lines: n / per, cut: false };
    return { node: sliced(node, Math.ceil(room * per)), lines: room, cut: true };
  }
  const kind = node[0];
  if (kind === "br") return { node, lines: 1, cut: false };
  if (kind === "code") return { node, lines: units(String(attrsOf(node)?.content ?? "")) / per, cut: false };
  const kids = kidsOf(node);
  if (!kids.length) return { node, lines: 0, cut: false };
  if (BLOCKS.has(kind) || kind === "pre" || kind === "p") return block(node, room, per);
  const t = taken(kids, room, true, per);
  return { node: t.cut ? withKids(node, t.kept) : node, lines: t.lines, cut: t.cut };
}

/// The beginning of `md` that fills `lines` lines or more however wide it is drawn; null when all of it may fill fewer.
export function mdHead(md: Md, lines: number): Md | null {
  const t = taken(md, lines, false, LINE);
  return t.cut ? t.kept : null;
}
/// The lines `md` fills at the least where a line holds `per` Latin letters, counted no further than `most`.
export function mdLines(md: Md, per: number, most: number): number {
  return Math.min(most, Math.ceil(taken(md, most, false, Math.max(1, per)).lines));
}
/// The same of plain words.
export function textLines(text: string, per: number, most: number): number {
  let lines = 0;
  for (let at = 0; at <= text.length && lines < most;) {
    const end = text.indexOf("\n", at);
    lines += Math.max(1, Math.ceil(units(end < 0 ? text.slice(at) : text.slice(at, end)) / Math.max(1, per)));
    if (end < 0) break;
    at = end + 1;
  }
  return Math.min(most, lines);
}
/// The same of plain words, drawn with their line breaks kept.
export function textHead(text: string, lines: number): string | null {
  let used = 0;
  let at = 0;
  while (at < text.length) {
    const end = text.indexOf("\n", at);
    const row = end < 0 ? text.slice(at) : text.slice(at, end);
    const n = Math.max(1, Math.ceil(units(row) / LINE));
    if (used + n >= lines) {
      const cut = at + sliced(row, (lines - used) * LINE).length;
      return cut < text.length ? text.slice(0, cut) : null;
    }
    used += n;
    if (end < 0) break;
    at = end + 1;
  }
  return null;
}
