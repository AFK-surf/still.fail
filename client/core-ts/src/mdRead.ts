// Markdown read into the nodes markdown.ts makes its tree of (mdast's, as far as it reads them), by markdown-it.
// micromark read it before: as GitHub's flavour, the same, but in Hermes (the phones' engine, which has no JIT) at
// ~370 000 characters a second on a Mac Studio, a chat's page of agents' replies ~0.2 s; markdown-it reads ten times
// as fast there (bench/md-parse.ts). What it reads as micromark's GFM did: tables, strikethrough with one tilde or
// two, task lists; raw HTML left out; links as written (not encoded, none refused: a client keeps what it may open);
// formulas in `$$` fences and `\[ \]` blocks, `\( \)` in a line (a `$` in prose is a dollar).
//
// The nodes say where in the text they stand where markdown.ts reads its runs from (`position`): a block by its lines,
// words by where they are found in turn in the text (they are the same characters wherever found).
import MarkdownIt from "markdown-it";
import cjkFriendly from "markdown-it-cjk-friendly";

// deno-lint-ignore no-explicit-any
type J = any;

/// mdast as far as markdown.ts reads it.
export type Node = { type: string; position?: { start: { offset?: number }; end: { offset?: number } }; children?: Node[]; value?: string; depth?: number; lang?: string | null; ordered?: boolean | null; start?: number | null; spread?: boolean | null; checked?: boolean | null; align?: (string | null)[] | null; url?: string; title?: string | null; alt?: string | null; identifier?: string; label?: string | null; referenceType?: string };

const reader = new MarkdownIt("default", { html: true, linkify: false, typographer: false });
// CommonMark's punctuation flanking rules can leave emphasis marks visible when CJK words have no spaces between them.
// Use the same delimiter scan for emphasis and the GFM tilde rule below, without changing the source's offsets.
reader.use(cjkFriendly);
reader.disable(["strikethrough"]);
// An address as written: not percent-encoded, none refused.
reader.normalizeLink = (url: string) => url;
reader.normalizeLinkText = (url: string) => url;
reader.validateLink = () => true;
reader.inline.ruler.before("emphasis", "tilde", tilde);
reader.inline.ruler2.before("emphasis", "tilde", tildePairs);
reader.inline.ruler.before("escape", "math_paren", mathParen);
const interrupts = { alt: ["paragraph", "reference", "blockquote", "list"] };
reader.block.ruler.before("fence", "math_fence", mathFence, interrupts);
reader.block.ruler.before("fence", "math_bracket", mathBracket, interrupts);

const isSpace = (c: number) => c === 0x20 || c === 0x09;

// ── strikethrough as GFM has it: a run of one tilde or two, closed by a run of as many ──

const ONE = 0x7e;
const TWO = 0x7e7e;

function tilde(state: J, silent: boolean): boolean {
  if (silent || state.src.charCodeAt(state.pos) !== ONE) return false;
  const scanned = state.scanDelims(state.pos, true);
  const token = state.push("text", "", 0);
  token.content = "~".repeat(scanned.length);
  // (three or more: words)
  if (scanned.length <= 2) state.delimiters.push({ marker: scanned.length === 1 ? ONE : TWO, length: 0, token: state.tokens.length - 1, end: -1, open: scanned.can_open, close: scanned.can_close });
  state.pos += scanned.length;
  return true;
}

function tildePairs(state: J): boolean {
  const pairs = (delimiters: J[]) => {
    for (const open of delimiters) {
      if ((open.marker !== ONE && open.marker !== TWO) || open.end === -1) continue;
      const close = delimiters[open.end];
      for (const [d, type, nesting] of [[open, "s_open", 1], [close, "s_close", -1]] as const) {
        const token = state.tokens[d.token];
        token.type = type;
        token.tag = "s";
        token.nesting = nesting;
        token.markup = token.content;
        token.content = "";
      }
    }
  };
  pairs(state.delimiters);
  for (const meta of state.tokens_meta) if (meta?.delimiters) pairs(meta.delimiters);
  return true;
}

// ── formulas ──

/// `$$` fenced, as a code fence is (its meta without a `$`).
function mathFence(state: J, startLine: number, endLine: number, silent: boolean): boolean {
  let pos = state.bMarks[startLine] + state.tShift[startLine];
  let max = state.eMarks[startLine];
  if (state.sCount[startLine] - state.blkIndent >= 4 || pos + 2 > max || state.src.charCodeAt(pos) !== 0x24) return false;
  let mem = pos;
  pos = state.skipChars(pos, 0x24);
  const size = pos - mem;
  if (size < 2) return false;
  const markup = state.src.slice(mem, pos);
  const params = state.src.slice(pos, max);
  if (params.includes("$")) return false;
  if (silent) return true;
  let next = startLine;
  let closed = false;
  for (;;) {
    next++;
    if (next >= endLine) break;
    pos = mem = state.bMarks[next] + state.tShift[next];
    max = state.eMarks[next];
    if (pos < max && state.sCount[next] < state.blkIndent) break;
    if (state.src.charCodeAt(pos) !== 0x24 || state.sCount[next] - state.blkIndent >= 4) continue;
    pos = state.skipChars(pos, 0x24);
    if (pos - mem < size) continue;
    pos = state.skipSpaces(pos);
    if (pos < max) continue;
    closed = true;
    break;
  }
  state.line = next + (closed ? 1 : 0);
  const token = state.push("math_block", "math", 0);
  token.info = params;
  token.content = state.getLines(startLine + 1, next, state.sCount[startLine], true);
  token.markup = markup;
  token.map = [startLine, state.line];
  return true;
}

/// `\[` at a line's start, to `\]` with nothing after it on its line; a backslash takes the character after it with it
/// (`\\]` closes nothing). It interrupts a paragraph on its opening alone, as micromark's did; open, it is no formula
/// (its `\[` an escaped bracket), nor where a line of it is not its container's (a lazy line, one left of a list).
function mathBracket(state: J, startLine: number, endLine: number, silent: boolean): boolean {
  const src: string = state.src;
  const first = state.bMarks[startLine] + state.tShift[startLine];
  if (state.sCount[startLine] - state.blkIndent >= 4 || src.charCodeAt(first) !== 0x5c || src.charCodeAt(first + 1) !== 0x5b) return false;
  if (silent) return true;
  let value = "";
  let line = startLine;
  let at = first + 2;
  let end = state.eMarks[line];
  for (;;) {
    while (at < end) {
      if (src.charCodeAt(at) === 0x5c) {
        if (src.charCodeAt(at + 1) === 0x5d) {
          let after = at + 2;
          while (after < end && isSpace(src.charCodeAt(after))) after++;
          if (after < end) return false;
          state.line = line + 1;
          const token = state.push("math_bracket", "math", 0);
          token.content = value;
          token.markup = "\\[";
          token.map = [startLine, state.line];
          return true;
        }
        const step = Math.min(2, end - at);
        value += src.slice(at, at + step);
        at += step;
        continue;
      }
      value += src[at];
      at++;
    }
    line++;
    if (line >= endLine) return false;
    const start = state.bMarks[line];
    end = state.eMarks[line];
    if (start + state.tShift[line] < end && state.sCount[line] < state.blkIndent) return false;
    // (the container's indent not the formula's)
    at = start;
    for (let column = 0; at < end && column < state.blkIndent && isSpace(src.charCodeAt(at)); column++) at++;
    value += "\n";
  }
}

/// `\(` to `\)` in a line's words, across its line breaks; a backslash takes the character after it with it. Open, it
/// is an escaped parenthesis.
function mathParen(state: J, silent: boolean): boolean {
  const src: string = state.src;
  const start = state.pos;
  if (src.charCodeAt(start) !== 0x5c || src.charCodeAt(start + 1) !== 0x28) return false;
  for (let at = start + 2; at < state.posMax; ) {
    if (src.charCodeAt(at) !== 0x5c) {
      at++;
      continue;
    }
    if (src.charCodeAt(at + 1) === 0x29) {
      if (!silent) {
        const token = state.push("math_inline", "math", 0);
        // (a line's leading spaces are not the formula's, as they are no paragraph's words)
        token.content = src.slice(start + 2, at).replace(/\n[ \t]+/g, "\n");
        token.markup = "\\(";
      }
      state.pos = at + 2;
      return true;
    }
    at += at + 1 < state.posMax && src.charCodeAt(at + 1) !== 0x0a ? 2 : 1;
  }
  return false;
}

// ── tokens into nodes ──

/// Where each line of `text` starts, as markdown-it counts lines (`\r\n`, `\r` and `\n` each end one).
function lineStarts(text: string): number[] {
  const starts = [0];
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 0x0a || (c === 0x0d && text.charCodeAt(i + 1) !== 0x0a)) starts.push(i + 1);
  }
  return starts;
}

type Walk = { source: string; starts: number[]; tokens: J[]; at: number };

/// The characters lines `from` to `to` (excluded) take.
function span(w: Walk, map: [number, number] | null | undefined): [number, number] {
  if (!map) return [0, w.source.length];
  const from = w.starts[map[0]] ?? w.source.length;
  const next = w.starts[map[1]];
  return [from, next === undefined ? w.source.length : next];
}

const at = (start: number, end: number) => ({ start: { offset: start }, end: { offset: end } });

/// `text` read: its root, its blocks under it.
export function read(text: string): Node {
  const w: Walk = { source: text, starts: lineStarts(text), tokens: reader.parse(text, {}), at: 0 };
  const root: Node = { type: "root", children: blocksOf(w, "") };
  return root;
}

/// The blocks from `w.at` to the token closing `until` (its type), that one passed.
function blocksOf(w: Walk, until: string): Node[] {
  const out: Node[] = [];
  while (w.at < w.tokens.length) {
    const t = w.tokens[w.at++];
    if (t.type === until) break;
    const node = blockOf(w, t);
    if (node) out.push(node);
  }
  return out;
}

function blockOf(w: Walk, t: J): Node | null {
  switch (t.type) {
    case "paragraph_open": {
      const inline = w.tokens[w.at]?.type === "inline" ? w.tokens[w.at++] : null;
      w.at++; // paragraph_close
      return { type: "paragraph", children: inline ? inlinesOf(w, inline.children ?? [], span(w, t.map)) : [] };
    }
    case "heading_open": {
      const inline = w.tokens[w.at]?.type === "inline" ? w.tokens[w.at++] : null;
      w.at++;
      return { type: "heading", depth: Number(String(t.tag).slice(1)) || 1, children: inline ? inlinesOf(w, inline.children ?? [], span(w, t.map)) : [] };
    }
    case "blockquote_open":
      return { type: "blockquote", children: blocksOf(w, "blockquote_close") };
    case "bullet_list_open":
    case "ordered_list_open": {
      const ordered = t.type === "ordered_list_open";
      const start = ordered ? Number(t.attrGet("start") ?? 1) : null;
      const close = ordered ? "ordered_list_close" : "bullet_list_close";
      const items: Node[] = [];
      // Tight as markdown-it marks it: an item's paragraphs hidden.
      let loose = false;
      while (w.at < w.tokens.length && w.tokens[w.at].type !== close) {
        const open = w.tokens[w.at++];
        if (open.type !== "list_item_open") continue;
        for (let i = w.at; i < w.tokens.length && w.tokens[i].level > open.level; i++) {
          if (w.tokens[i].type === "paragraph_open" && w.tokens[i].level === open.level + 1 && !w.tokens[i].hidden) loose = true;
        }
        items.push(task({ type: "listItem", spread: false, children: blocksOf(w, "list_item_close") }));
      }
      w.at++;
      return { type: "list", ordered, start, spread: loose, children: items };
    }
    case "fence":
    case "code_block":
    case "math_block":
    case "math_bracket": {
      const [from, to] = span(w, t.map);
      const lead = t.type === "code_block" ? -1 : w.source.indexOf(t.markup, from);
      const position = at(lead >= 0 && lead < to ? lead : from, trimEnd(w.source, to));
      if (t.type === "math_bracket") return { type: "inlineMath", value: t.content, position };
      const value = String(t.content).replace(/\n$/, "");
      if (t.type === "math_block") return { type: "math", value, position };
      const lang = t.type === "fence" ? String(t.info ?? "").trim().split(/\s+/)[0] || null : null;
      return { type: "code", lang, value, position };
    }
    case "hr":
      return { type: "thematicBreak" };
    case "html_block":
      return { type: "html" };
    case "table_open":
      return tableOf(w, t);
    default:
      return null;
  }
}

/// Where a block's characters end: before the line ending after its last line.
function trimEnd(source: string, to: number): number {
  let end = to;
  if (source.charCodeAt(end - 1) === 0x0a) end--;
  if (source.charCodeAt(end - 1) === 0x0d) end--;
  return end;
}

function tableOf(w: Walk, open: J): Node {
  const rows: Node[] = [];
  let align: (string | null)[] = [];
  while (w.at < w.tokens.length && w.tokens[w.at].type !== "table_close") {
    const t = w.tokens[w.at++];
    if (t.type !== "tr_open") continue;
    const cells: Node[] = [];
    const head = rows.length === 0;
    while (w.at < w.tokens.length && w.tokens[w.at].type !== "tr_close") {
      const c = w.tokens[w.at++];
      if (c.type !== "th_open" && c.type !== "td_open") continue;
      if (head) {
        const style = String(c.attrGet("style") ?? "");
        align.push(style.startsWith("text-align:") ? style.slice(11) : null);
      }
      const inline = w.tokens[w.at]?.type === "inline" ? w.tokens[w.at++] : null;
      w.at++; // th_close, td_close
      // (`value`: the cell as written, between its bars, an escaped bar a bar: what the table as Markdown is made of)
      cells.push({ type: "tableCell", value: inline ? String(inline.content ?? "") : "", children: inline ? inlinesOf(w, inline.children ?? [], span(w, t.map)) : [] });
    }
    w.at++;
    rows.push({ type: "tableRow", children: cells });
  }
  w.at++;
  if (rows.length === 0) align = [];
  return { type: "table", align, children: rows, position: at(...span(w, open.map)) };
}

/// A list item that is a task, as GFM reads one: its first paragraph begins `[ ]` or `[x]`, then a space or a line's
/// end, and something follows; the check said by `checked`, and its words without it.
function task(item: Node): Node {
  const p = item.children?.[0];
  const head = p?.type === "paragraph" ? p.children?.[0] : undefined;
  if (!p || head?.type !== "text") return item;
  const kids = p.children!;
  const v = head.value ?? "";
  const m = /^\[([ \t\n\rxX])\]/.exec(v);
  if (!m) return item;
  const next = v.charCodeAt(3);
  // then a line's end (what follows on the next line), or spaces and then something (on this line, or after this text)
  if (next !== 0x0a && next !== 0x0d && (!isSpace(next) || (v.slice(4).trim() === "" && kids.length <= 1))) return item;
  item.checked = m[1] === "x" || m[1] === "X";
  const rest = v.slice(4);
  if (rest === "") kids.shift();
  else {
    head.value = rest;
    const start = head.position?.start.offset;
    if (start !== undefined) head.position!.start.offset = start + 4;
  }
  return item;
}

// ── a line's words ──

/// The inline tokens of a block whose characters are `[from, to)`: as nodes, its words found in turn there.
function inlinesOf(w: Walk, tokens: J[], [from, to]: [number, number]): Node[] {
  const cursor = { at: from, to };
  let i = 0;
  const until = (close: string): Node[] => {
    const out: Node[] = [];
    while (i < tokens.length) {
      const t = tokens[i++];
      if (t.type === close) break;
      // Words and the line breaks between them one text, as mdast has them: one run where they stand together in the
      // text, else the words themselves (lines of a quote or a list, their marks between them).
      if (t.type === "text" || t.type === "softbreak") {
        const pieces = [t.type === "text" ? String(t.content) : "\n"];
        while (i < tokens.length && (tokens[i].type === "text" || tokens[i].type === "softbreak")) pieces.push(tokens[i].type === "text" ? String(tokens[i++].content) : (i++, "\n"));
        const value = pieces.join("");
        const from = cursor.at;
        const position = found(value);
        if (!position && pieces.length > 1) {
          // (on past them all the same, for what follows to be found after them)
          cursor.at = from;
          for (const piece of pieces) found(piece);
        }
        out.push({ type: "text", value, ...(position ? { position } : {}) });
        continue;
      }
      const node = inlineOf(t);
      if (node) out.push(node);
    }
    return out;
  };
  const found = (words: string): Node["position"] => {
    if (words === "") return undefined;
    const k = w.source.indexOf(words, cursor.at);
    if (k < 0 || k + words.length > cursor.to) return undefined;
    cursor.at = k + words.length;
    return at(k, k + words.length);
  };
  const inlineOf = (t: J): Node | null => {
    switch (t.type) {
      case "hardbreak":
        return { type: "break" };
      case "code_inline": {
        const k = w.source.indexOf(t.markup, cursor.at);
        if (k >= 0 && k < cursor.to) cursor.at = k;
        const start = k >= 0 && k < cursor.to ? k : undefined;
        const inside = found(t.content);
        if (inside) cursor.at += t.markup.length;
        return { type: "inlineCode", value: t.content, ...(start !== undefined ? { position: at(start, cursor.to) } : {}) };
      }
      case "math_inline": {
        const k = w.source.indexOf("\\(", cursor.at);
        const start = k >= 0 && k < cursor.to ? k : undefined;
        if (start !== undefined) cursor.at = start + 2;
        const inside = found(t.content);
        if (inside) cursor.at += 2;
        return { type: "inlineMath", value: t.content, ...(start !== undefined ? { position: at(start, cursor.to) } : {}) };
      }
      case "em_open":
        return { type: "emphasis", children: until("em_close") };
      case "strong_open":
        return { type: "strong", children: until("strong_close") };
      case "s_open":
        return { type: "delete", children: until("s_close") };
      case "link_open":
        return { type: "link", url: String(t.attrGet("href") ?? ""), title: t.attrGet("title") ?? null, children: until("link_close") };
      case "image":
        return { type: "image", url: String(t.attrGet("src") ?? ""), alt: plain(t.children ?? []), title: t.attrGet("title") ?? null };
      case "html_inline":
        return { type: "html" };
      default: {
        if (!t.content) return null;
        const position = found(t.content);
        return { type: "text", value: t.content, ...(position ? { position } : {}) };
      }
    }
  };
  return until("");
}

/// What an image's words say, without their marks.
function plain(tokens: J[]): string {
  return tokens.map((t: J) => (t.type === "image" ? plain(t.children ?? []) : t.type === "softbreak" || t.type === "hardbreak" ? "\n" : String(t.content ?? ""))).join("");
}
