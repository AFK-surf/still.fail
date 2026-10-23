// A text file as a reader shows it, worked out once, here, for every client (the Android app's drive/TextModel.kt and
// Novel.kt, zdrive's reader, as the web's reader had them): its line ends made one, a novel hard-wrapped at a fixed
// width joined back into its paragraphs (Markdown never: it is laid out line by line already), its chapters found
// (第X章…, front and back matter, Chapter N, a short line that looks like a title; Markdown's headings), the lines that
// are headings by the strict rules (a client does not indent them), and where words are in it. The bytes are decoded
// by the client (the system's tables: a novel in GB18030), which hands the text over. A Markdown file is read as a
// chat's words are (markdown.ts, the same tree): its chapters are its headings as that reads them, and its words are
// found where they are drawn (its marks are not searched), each told by where it stands in the text.
//
// A client asks `reader.book` with the text (its UTF-8 beside the call) and is answered the book's id, how it was
// wrapped, its length, its chapters and heading lines (and a Markdown book's tree); `reader.text` gives the text as
// joined (its UTF-8 beside the answer) where joining changed it; `reader.search` finds words in it. The latest books
// are kept by their id.
import { type Md, type MdNode, markdown as readMarkdown, plainOf } from "./markdown.ts";
import { wordsOf } from "./mdWords.ts";

/** A chapter heading: its words and where it starts in the text. */
export interface Chapter { title: string; offset: number }

/** A text as the reader has it: the text (joined), the column it was wrapped at (0: none), its chapters, the starts of
 *  its lines that are headings by the strict rules, a Markdown file's tree (markdown.ts). */
export interface Book { text: string; wrapped: number; chapters: Chapter[]; heads: number[]; md: Md | null }

export const normaliseLineEnds = (text: string) => (text.includes("\r") ? text.replace(/\r\n?/g, "\n") : text);

const endsSentence = (c: string) => "。！？…\"”」』)）".includes(c);
const isBlank = (c: string) => c === " " || c === "\t" || c === "　" || c === "﻿";

/**
 * The column a hard-wrapped file was broken at, or 0. Most of its lines sit right at the widest, few end a sentence:
 * a file of a paragraph a line spreads its lengths out and does not match (joining its lines would weld paragraphs).
 */
export function wrapWidth(text: string): number {
  const SAMPLE = 200_000;
  let widest = 0, lines = 0;
  for (let i = 0; i < text.length && i < SAMPLE && lines < 2000;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    if (end > i) { lines++; widest = Math.max(widest, end - i); }
    if (nl < 0) break;
    i = nl + 1;
  }
  if (lines < 12 || widest < 20 || widest > 160) return 0;
  const band = Math.floor((widest * 4) / 5);
  let seen = 0, full = 0, atMax = 0, terminal = 0;
  for (let i = 0; i < text.length && i < SAMPLE && seen < lines;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    const length = end - i;
    if (length > 0) {
      seen++;
      if (length >= band) full++;
      if (length >= widest - 2) atMax++;
      if (endsSentence(text[end - 1]!)) terminal++;
    }
    if (nl < 0) break;
    i = nl + 1;
  }
  return full * 5 >= seen * 2 && atMax >= 5 && terminal * 2 <= seen ? widest : 0;
}

const isCjk = (c: string) => {
  const n = c.charCodeAt(0);
  return (n >= 0x2e80 && n <= 0x30ff) || (n >= 0x3400 && n <= 0x4dbf) || (n >= 0x4e00 && n <= 0x9fff) || (n >= 0xf900 && n <= 0xfaff) || (n >= 0xfe30 && n <= 0xfe4f) || (n >= 0xff00 && n <= 0xffef);
};

/** The line breaks the source put in joined (a space between Latin words), those that end a paragraph kept, and the
 *  lines at `keep` (headings) and those that start indented always starting one. A join stops at 4000 characters. */
export function reflow(text: string, width: number, keep: ReadonlySet<number>): string {
  if (width <= 0) return text;
  const band = Math.floor((width * 4) / 5);
  const out: string[] = [];
  let size = 0, last = "", previousFull = false, joined = 0;
  for (let i = 0; i < text.length;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    const length = end - i;
    // A line that starts indented starts a paragraph: a line the source broke never is.
    const continuation = length > 0 && !keep.has(i) && !isBlank(text[i]!) && previousFull && size > 0 && joined < 4000;
    if (continuation) {
      if (last !== " " && last !== "\n" && last !== "-" && !isCjk(last) && !isCjk(text[i]!)) { out.push(" "); size++; last = " "; }
    } else {
      if (size > 0) { out.push("\n"); size++; last = "\n"; }
      joined = 0;
    }
    const line = text.slice(i, end);
    out.push(line);
    size += line.length;
    if (line.length) last = line[line.length - 1]!;
    joined += length;
    previousFull = length >= band;
    if (nl < 0) break;
    i = nl + 1;
  }
  return out.join("");
}

const NUMERALS = "0-9０-９零〇一二三四五六七八九十百千万两";
const CJK_HEADING = new RegExp(`^(?:正文[\\s:：·　]*)?第\\s*[${NUMERALS}]{1,12}\\s*[章卷回节篇部集话](?:[\\s:：.、·　\\-—]?[^\\n]{0,36})?$`);
const FRONT_MATTER = /^(?:序章|序言|楔子|引子|前言|序幕|尾声|终章|番外\d{0,3}|后记|外传|附录).{0,36}$/;
const LATIN_HEADING = /^(?:Chapter|CHAPTER|chapter)\s{0,2}[0-9]{1,4}[^\n]{0,30}$/;
const TITLE_STOP = "。！？；，、：…—～·\"'“”‘’()（）[]【】《》〈〉「」『』";

/** Whether a line (its blanks trimmed) is a heading by the strict rules: 第X章, front and back matter, Chapter N. */
export function isHeading(line: string): boolean {
  return line.length >= 2 && line.length <= 48 && (CJK_HEADING.test(line) || FRONT_MATTER.test(line) || LATIN_HEADING.test(line));
}

/** Each line of `text`: where it starts and where its words (its blanks trimmed) start and end. */
function* linesOf(text: string): Generator<{ start: number; from: number; to: number; next: number }> {
  for (let i = 0; i < text.length;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    let b = i, f = end;
    while (b < f && isBlank(text[b]!)) b++;
    while (f > b && isBlank(text[f - 1]!)) f--;
    yield { start: i, from: b, to: f, next: nl < 0 ? -1 : nl + 1 };
    if (nl < 0) break;
    i = nl + 1;
  }
}

/**
 * Its chapters, best effort: the strict headings, and with `weak` short lines that look like titles (no sentence
 * punctuation, after a blank line or a sentence's end, at least 200 characters after the last one).
 */
export function findChapters(text: string, weak = true, limit = 2000): Chapter[] {
  const found: Chapter[] = [];
  let previousBlank = true, previousSentence = true, last = -200;
  for (const { start: i, from: b, to: f } of linesOf(text)) {
    if (found.length >= limit) break;
    const length = f - b;
    if (length >= 2 && length <= 48) {
      const line = text.slice(b, f);
      if (isHeading(line)) {
        found.push({ title: line, offset: i });
        last = i;
      } else if (weak && length <= 20 && ![...line].some((c) => TITLE_STOP.includes(c)) && (previousBlank || previousSentence) && i - last >= 200) {
        found.push({ title: line, offset: i });
        last = i;
      }
    }
    previousBlank = length === 0;
    previousSentence = length > 0 && (isBlank(text[f - 1]!) || endsSentence(text[f - 1]!));
  }
  return found;
}

/** Where each line of `text` that is a heading by the strict rules starts. */
export function headingLines(text: string): number[] {
  const found: number[] = [];
  for (const { start, from, to } of linesOf(text)) {
    if (to - from >= 2 && to - from <= 48 && isHeading(text.slice(from, to))) found.push(start);
  }
  return found;
}

/** The first place in the text a node's words stand, or -1 (words of its own, as an escape's, have none). */
function firstAt(node: MdNode): number {
  if (typeof node === "string") return -1;
  if (typeof node[0] === "number") return node[0];
  const [, first, second] = node as [string, unknown, unknown];
  const attrs = ((Array.isArray(first) ? second : first) ?? {}) as Record<string, unknown>;
  for (const words of [attrs.code, attrs.content]) if (Array.isArray(words) && typeof words[0] === "number") return words[0];
  if (Array.isArray(first)) {
    for (const child of first as MdNode[]) {
      const at = firstAt(child);
      if (at >= 0) return at;
    }
  }
  return -1;
}

/** A Markdown file's chapters: its headings of levels 1 to 3 (as markdown.ts reads them, none in code), each where its
 *  line starts. */
export function markdownChapters(text: string, md: Md = readMarkdown(text), limit = 2000): Chapter[] {
  const found: Chapter[] = [];
  for (const node of md) {
    if (typeof node === "string" || typeof node[0] === "number" || node[0] !== "h") continue;
    const depth = Number(((node as [string, unknown, Record<string, unknown>])[2] ?? {}).depth ?? 1);
    const at = firstAt(node);
    const title = plainOf([node], text).trim();
    if (depth > 3 || at < 0 || !title) continue;
    found.push({ title, offset: text.lastIndexOf("\n", at - 1) + 1 });
    if (found.length >= limit) break;
  }
  return found;
}

/** A Markdown book's words as drawn, its marks gone (each block on a line of its own), and where each of them stands
 *  in the text (words of their own, as an escape's: where the words before them end). */
export function shownWords(md: Md, text: string): { words: string; at: number[] } {
  const out: string[] = [];
  const at: number[] = [];
  let last = 0, tail = "\n";
  const put = (words: string, from: number) => {
    if (!words) return;
    for (let i = 0; i < words.length; i++) at.push(from >= 0 ? from + i : last);
    if (from >= 0) last = from + words.length;
    out.push(words);
    tail = words[words.length - 1]!;
  };
  const apart = () => { if (tail !== "\n") put("\n", -1); };
  const run = (words: unknown) => {
    if (Array.isArray(words) && typeof words[0] === "number") put(wordsOf(words, text), words[0]);
    else put(wordsOf(words, text), -1);
  };
  const BLOCKS = new Set(["p", "h", "pre", "quote", "list", "li", "table", "tr", "hr"]);
  const walk = (node: MdNode) => {
    if (typeof node === "string" || typeof node[0] === "number") { run(node); return; }
    const [kind, first, second] = node as [string, unknown, unknown];
    const attrs = ((Array.isArray(first) ? second : first) ?? {}) as Record<string, unknown>;
    if (BLOCKS.has(kind)) apart();
    if (kind === "th" || kind === "td") put(" ", -1);
    if (kind === "pre") run(attrs.code);
    else if (kind === "code") run(attrs.content);
    else if (kind === "img") put(String(attrs.alt ?? ""), -1);
    else if (kind === "br") put("\n", -1);
    else if (Array.isArray(first)) for (const child of first as MdNode[]) walk(child);
  };
  for (const node of md) walk(node);
  return { words: out.join(""), at };
}

/** `text` (decoded by the client) as the reader shows it; `markdown`: a Markdown file's. */
export function book(text: string, markdown: boolean): Book {
  const plain = normaliseLineEnds(text);
  if (markdown) {
    const md = readMarkdown(plain);
    return { text: plain, wrapped: 0, chapters: markdownChapters(plain, md), heads: [], md };
  }
  // (Markdown is laid out line by line already: joining its lines would weld a heading into the paragraph under it.)
  const width = wrapWidth(plain);
  // Headings found before joining, so none is welded into the paragraph above it; found again after, where lines are
  // paragraphs and "a short line with no punctuation" means a title.
  const keep = width > 0 ? new Set(findChapters(plain, false).map((c) => c.offset)) : new Set<number>();
  const joined = width > 0 ? reflow(plain, width, keep) : plain;
  return { text: joined, wrapped: width, chapters: findChapters(joined), heads: headingLines(joined), md: null };
}

/** Every place `query` is in a book (up to `limit`): in a Markdown book's words as drawn, told by where they stand in
 *  its text. */
export function searchBook(b: Book, query: string, limit = 500): number[] {
  if (!b.md) return search(b.text, query, limit);
  const { words, at } = shownWords(b.md, b.text);
  return search(words, query, limit).map((i) => at[i]!);
}

/** Every place `query` is in `text` (up to `limit`); Latin letters matched without case when it is found no other way. */
export function search(text: string, query: string, limit = 500): number[] {
  const found: number[] = [];
  if (!query) return found;
  for (let i = text.indexOf(query); i >= 0 && found.length < limit; i = text.indexOf(query, i + query.length)) found.push(i);
  if (found.length || !/[A-Za-z]/.test(query)) return found;
  const lower = text.toLowerCase(), q = query.toLowerCase();
  if (lower.length !== text.length || q.length !== query.length) return found;
  for (let i = lower.indexOf(q); i >= 0 && found.length < limit; i = lower.indexOf(q, i + q.length)) found.push(i);
  return found;
}

/** What `reader.book` answers of a book kept as `id` (`given`: the text as the client gave it): `text` with `withText`, a
 *  Markdown book's tree with `tree`. */
export function bookAnswer(id: number, b: Book, given: string, opts: { withText?: boolean; tree?: boolean } = {}) {
  return {
    id,
    length: b.text.length,
    wrapped: b.wrapped,
    joined: b.text !== given,
    chapters: b.chapters,
    heads: b.heads,
    ...(opts.withText ? { text: b.text } : {}),
    ...(opts.tree && b.md ? { md: b.md } : {}),
  };
}

/// The books a client asked of lately, by their id (a reader has one open at a time; a few are kept for going back).
const books = new Map<number, Book>();
let nextBook = 1;
const KEPT_BOOKS = 3;

/** The book of `text` kept, and its id: what a client asks with afterwards (`reader.text`, `reader.search`). */
export function keepBook(text: string, markdown: boolean): { id: number; book: Book } {
  const b = book(text, markdown);
  const id = nextBook++;
  books.set(id, b);
  for (const old of books.keys()) {
    if (books.size <= KEPT_BOOKS) break;
    books.delete(old);
  }
  return { id, book: b };
}

/** A kept book by its id, if it is still kept. */
export function keptBook(id: number): Book | undefined {
  return books.get(id);
}
