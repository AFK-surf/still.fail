// What the reader shows of a text file, worked out from its bytes (zdrive's reader/TextModel.kt): decoded (UTF-8, else
// GB18030, as Chinese novels often are), line ends made one, a novel hard-wrapped at a fixed width joined back into
// its paragraphs (Markdown never), and its chapters found (第X章…, Chapter N; Markdown's headings). Plain functions over
// a string: textWorker.ts runs them off the page's thread.

/** A chapter heading: its words and where it starts in the text. */
export interface Chapter { title: string; offset: number }

/** A text as the reader has it. `starts`: where each of its lines (paragraphs) starts. */
export interface Book { text: string; encoding: string; chapters: Chapter[]; markdown: boolean; starts: Int32Array; wrapped: number }

/** Bytes as text: by their byte order mark, else UTF-8 when they are, else GB18030. `cut`: these are a file's front
 *  only, so a character cut at their end is no sign they are not UTF-8. */
export function decodeText(bytes: Uint8Array, cut = false): { text: string; encoding: string } {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return { text: new TextDecoder("utf-8").decode(bytes.subarray(3)), encoding: "UTF-8" };
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) return { text: new TextDecoder("utf-16le").decode(bytes.subarray(2)), encoding: "UTF-16LE" };
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) return { text: new TextDecoder("utf-16be").decode(bytes.subarray(2)), encoding: "UTF-16BE" };
  const strict = new TextDecoder("utf-8", { fatal: true });
  try {
    return { text: strict.decode(bytes, { stream: cut }), encoding: "UTF-8" };
  } catch {
    // A file whose own last character is cut short (half copied) is still UTF-8.
    try {
      return { text: strict.decode(bytes.subarray(0, tailStart(bytes))), encoding: "UTF-8" };
    } catch {
      // not UTF-8
    }
  }
  try {
    return { text: new TextDecoder("gb18030").decode(bytes), encoding: "GB18030" };
  } catch {
    return { text: new TextDecoder("latin1").decode(bytes), encoding: "ISO-8859-1" };
  }
}

/** Where a UTF-8 character cut at the end of `bytes` starts (its length when none is). */
function tailStart(bytes: Uint8Array): number {
  for (let i = bytes.length - 1, n = 0; i >= 0 && n < 4; i--, n++) {
    const b = bytes[i]!;
    if ((b & 0xc0) === 0x80) continue;
    const need = b >= 0xf0 ? 4 : b >= 0xe0 ? 3 : b >= 0xc0 ? 2 : 1;
    return n + 1 < need ? i : bytes.length;
  }
  return bytes.length;
}

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
 *  lines at `keep` (headings) always starting one. A join stops at 4000 characters. */
export function reflow(text: string, width: number, keep: ReadonlySet<number>): string {
  if (width <= 0) return text;
  const band = Math.floor((width * 4) / 5);
  const out: string[] = [];
  let size = 0, last = "", previousFull = false, joined = 0;
  for (let i = 0; i < text.length;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    const length = end - i;
    const continuation = length > 0 && !keep.has(i) && previousFull && size > 0 && joined < 4000;
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

/**
 * Its chapters, best effort: the strict headings, and with `weak` short lines that look like titles (no sentence
 * punctuation, after a blank line or a sentence's end, at least 200 characters after the last one).
 */
export function findChapters(text: string, weak = true, limit = 2000): Chapter[] {
  const found: Chapter[] = [];
  let previousBlank = true, previousSentence = true, last = -200;
  for (let i = 0; i < text.length && found.length < limit;) {
    const nl = text.indexOf("\n", i);
    const end = nl < 0 ? text.length : nl;
    let b = i, f = end;
    while (b < f && isBlank(text[b]!)) b++;
    while (f > b && isBlank(text[f - 1]!)) f--;
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
    if (nl < 0) break;
    i = nl + 1;
  }
  return found;
}

/** A Markdown file's headings (levels 1 to 3), not those in fenced code. */
export function markdownChapters(text: string, limit = 2000): Chapter[] {
  const found: Chapter[] = [];
  let at = 0, fenced = false;
  for (const line of text.split("\n")) {
    const start = at;
    at += line.length + 1;
    const trimmed = line.trimStart();
    if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) { fenced = !fenced; continue; }
    if (fenced) continue;
    const m = /^(#{1,3})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    found.push({ title: m[2]!.trim(), offset: start });
    if (found.length >= limit) break;
  }
  return found;
}

/** A file's bytes as the reader shows them. */
export function book(bytes: Uint8Array, markdown: boolean, cut: boolean): Book {
  const decoded = decodeText(bytes, cut);
  const plain = normaliseLineEnds(decoded.text);
  // Markdown is laid out line by line already: joining its lines would weld a heading into the paragraph under it.
  const width = markdown ? 0 : wrapWidth(plain);
  // Headings found before joining, so none is welded into the paragraph above it; found again after, where lines are
  // paragraphs and "a short line with no punctuation" means a title.
  const keep = width > 0 ? new Set(findChapters(plain, false).map((c) => c.offset)) : new Set<number>();
  const text = width > 0 ? reflow(plain, width, keep) : plain;
  const chapters = markdown ? markdownChapters(text) : findChapters(text);
  const starts: number[] = [0];
  for (let i = text.indexOf("\n"); i >= 0; i = text.indexOf("\n", i + 1)) starts.push(i + 1);
  return { text, encoding: decoded.encoding, chapters, markdown, starts: Int32Array.from(starts), wrapped: width };
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
