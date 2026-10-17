// The text side of the reader (drive/TextModel.kt): decoding, line reflow, chunking, chapter markers, search and the
// offset arithmetic the rendered blocks are drawn with.
//
// Everything here is plain TypeScript over a string — no React Native, no views — so the part of the reader that
// decides *what* is shown can be checked without a device. The screen only decides how it looks.
//
// Strings are UTF-16 here as Kotlin's are, so every offset (a chunk's start, a match, where the reader was left) is the
// same number on both apps.
import { TextDecoder } from "@zxing/text-encoding";

/** A decoded file, with the encoding that produced it. */
export interface DecodedText { text: string; encoding: string }

/** A chapter heading, as an offset into the text the reader renders. */
export interface ChapterMark { title: string; offset: number }

/** A heading the table of contents can jump to. [offset] is inside [chunk]. */
export interface NovelChapter { title: string; chunk: number; offset: number }

/** A substring of the text the reader renders, tagged with the chunk it belongs to. */
export interface TextMatch { chunk: number; start: number; length: number }

/** The text cut into blocks small enough to lay out one at a time. */
export interface ChunkedText { chunks: string[]; starts: number[] }

/**
 * How much text one block holds.
 *
 * A block has to be small enough that laying it out is cheap and big enough that the list does not hold thousands of
 * blocks; ~1k characters is 2–3 phone pages, which also keeps "where I left off" honest to within a page or two.
 */
export const CHUNK_CHARS = 1000;

/** Two ideographic spaces, which is what a Chinese paragraph is indented by. */
export const INDENT = "　　";

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/**
 * Decodes raw file bytes.
 *
 * Strict UTF-8 is tried before GB18030, and in that order on purpose: a GB18030 novel is very often valid UTF-8 for
 * hundreds of bytes before the first bad sequence, so asking GB18030 first would mojibake every file that really is
 * UTF-8, while strict UTF-8 can only fail a file that really is GB18030. The fallback decodes leniently, so no byte
 * sequence can throw — a novel with a corrupt page still opens, with replacement characters where the damage is.
 *
 * [truncated] means these bytes are the front of a larger file. A multi-byte character cut in half at the end is then
 * dropped rather than treated as evidence that the whole file is not UTF-8.
 */
export function decodeText(bytes: Uint8Array, offset = 0, length: number = bytes.length, truncated = false): DecodedText {
  if (length <= 0 || offset >= bytes.length) return { text: "", encoding: "UTF-8" };
  const end = Math.min(offset + length, bytes.length);
  const bom = sniffBom(bytes, offset, end - offset);
  if (bom !== null) {
    const from = offset + bom.bytes;
    // A byte order mark settles the encoding; there is nothing to guess.
    const text = decodeBlocks(bytes, from, end, bom.charset, true, truncated)
      ?? decodeBlocks(bytes, from, end, bom.charset, false, truncated)
      ?? "";
    return { text, encoding: bom.label };
  }
  const strict = decodeBlocks(bytes, offset, end, "utf-8", true, truncated);
  if (strict !== null) return { text: strict, encoding: "UTF-8" };
  if (!truncated) {
    // A file whose own last character is incomplete — a half-copied download — is still UTF-8, and must not be re-read
    // as GB18030.
    const cutTail = decodeBlocks(bytes, offset, end, "utf-8", true, true);
    if (cutTail !== null) return { text: cutTail, encoding: "UTF-8" };
  }
  // Not UTF-8. GB18030 is a superset of GBK and the usual answer for older Chinese text; ISO-8859-1 is the floor that
  // cannot fail.
  if (!decoderFor("gb18030", false)) {
    let latin = "";
    for (let i = offset; i < end; i++) latin += String.fromCharCode(bytes[i]!);
    return { text: latin, encoding: "ISO-8859-1" };
  }
  const text = decodeBlocks(bytes, offset, end, "gb18030", false, truncated);
  return { text: text ?? "", encoding: "GB18030" };
}

interface Bom { charset: string; bytes: number; label: string }

function sniffBom(bytes: Uint8Array, offset: number, length: number): Bom | null {
  if (length >= 3 && bytes[offset] === 0xef && bytes[offset + 1] === 0xbb && bytes[offset + 2] === 0xbf) return { charset: "utf-8", bytes: 3, label: "UTF-8 BOM" };
  if (length >= 2 && bytes[offset] === 0xff && bytes[offset + 1] === 0xfe) return { charset: "utf-16le", bytes: 2, label: "UTF-16LE" };
  if (length >= 2 && bytes[offset] === 0xfe && bytes[offset + 1] === 0xff) return { charset: "utf-16be", bytes: 2, label: "UTF-16BE" };
  return null;
}

/** A decoder for `charset` (`fatal`: strict), null where none is known. */
function decoderFor(charset: string, fatal: boolean): TextDecoder | null {
  try {
    // The mark is skipped already (sniffBom): what follows it is text, a second mark included.
    return new TextDecoder(charset, { fatal, ignoreBOM: true });
  } catch {
    return null;
  }
}

/**
 * Decodes through one streaming decoder (the WHATWG TextDecoder, the same rules as Java's for the encodings here).
 *
 * Returns null only when [strict] decoding hits a byte it cannot map. With [dropTail] the decoder is told more is
 * coming (`stream`), so it holds an incomplete last character back rather than turning it into a replacement character.
 */
function decodeBlocks(bytes: Uint8Array, from: number, to: number, charset: string, strict: boolean, dropTail: boolean): string | null {
  if (from >= to) return "";
  const decoder = decoderFor(charset, strict);
  if (!decoder) return null;
  try {
    return decoder.decode(bytes.subarray(from, to), { stream: dropTail });
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Line reflow
// ---------------------------------------------------------------------------

/** Line endings normalised to `\n`; the same string when there is nothing to do. */
export function normaliseLineEndings(text: string): string {
  if (text.indexOf("\r") < 0) return text;
  return text.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
}

/**
 * The column a hard-wrapped file was broken at, or 0 when it was not.
 *
 * Downloaded Chinese novels are commonly wrapped at a fixed width (40 characters is typical) rather than one paragraph
 * per line. Laid out on a phone, every one of those source lines would become a short ragged line of its own, and pages
 * would end a third of the way down. Wrapping is recognised by the signature it leaves: most non-empty lines sit right
 * at the maximum width. Paragraph-per-line files spread their line lengths out, so they do not match, which matters
 * because joining *their* lines would merge paragraphs.
 */
export function detectWrapWidth(text: string): number {
  const sampleChars = 200_000;
  const sampleLines = 2_000;
  let widest = 0;
  let lines = 0;
  let index = 0;
  while (index < text.length && index < sampleChars && lines < sampleLines) {
    const newline = text.indexOf("\n", index);
    const end = newline < 0 ? text.length : newline;
    if (end > index) {
      lines++;
      if (end - index > widest) widest = end - index;
    }
    if (newline < 0) break;
    index = newline + 1;
  }
  if (lines < 12 || widest < 20 || widest > 160) return 0;
  const band = Math.trunc((widest * 4) / 5);
  let seen = 0;
  let full = 0;
  let atMax = 0;
  let terminal = 0;
  index = 0;
  while (index < text.length && index < sampleChars && seen < lines) {
    const newline = text.indexOf("\n", index);
    const end = newline < 0 ? text.length : newline;
    const length = end - index;
    if (length > 0) {
      seen++;
      if (length >= band) full++;
      if (length >= widest - 2) atMax++;
      // A paragraph ends in punctuation; a wrapped line usually does not.
      if (end > index && endsSentence(text[end - 1]!)) terminal++;
    }
    if (newline < 0) break;
    index = newline + 1;
  }
  // Deliberately tight, in both directions: a false positive joins real paragraphs together, which reads far worse than
  // a wrapped file left alone.
  return full * 5 >= seen * 2 && atMax >= 5 && terminal * 2 <= seen ? widest : 0;
}

/**
 * Joins the line breaks that the source put there, keeping the ones that mean a paragraph.
 *
 * [keepLineStarts] are offsets of lines that must start a paragraph regardless (chapter headings, which would otherwise
 * be swallowed by the paragraph above them). A join stops after [MAX_JOINED] characters, so a file that only looks
 * wrapped cannot be welded into one enormous line.
 */
export function reflow(text: string, wrapWidth: number, keepLineStarts: ReadonlySet<number>): string {
  if (wrapWidth <= 0) return text;
  const band = Math.trunc((wrapWidth * 4) / 5);
  const out: string[] = [];
  let outLength = 0;
  let last = "";
  let index = 0;
  let previousFull = false;
  let joined = 0;
  const append = (s: string) => { if (s.length === 0) return; out.push(s); outLength += s.length; last = s[s.length - 1]!; };
  while (index < text.length) {
    const newline = text.indexOf("\n", index);
    const end = newline < 0 ? text.length : newline;
    const length = end - index;
    const blank = length === 0;
    // An indented line starts a paragraph: a wrapped line never begins with the paragraph's indent.
    const keep = keepLineStarts.has(index) || (length > 0 && (text[index] === "　" || text.startsWith("  ", index)));
    const continuation = !blank && !keep && previousFull && outLength > 0 && joined < MAX_JOINED;
    if (continuation) {
      // The break replaced a space in Latin text; Chinese needs no space.
      if (needsSpace(last, text, index)) append(" ");
    } else {
      if (outLength > 0) append("\n");
      joined = 0;
    }
    append(text.substring(index, end));
    joined += length;
    previousFull = length >= band;
    if (newline < 0) break;
    index = newline + 1;
  }
  return out.join("");
}

const MAX_JOINED = 4000;

function needsSpace(last: string, text: string, next: number): boolean {
  if (next >= text.length) return false;
  if (last === " " || last === "\n" || last === "-") return false;
  return !isCjk(last) && !isCjk(text[next]!);
}

/** Rough CJK test: the ranges a Chinese novel lives in, plus full-width punctuation. */
function isCjk(char: string): boolean {
  const c = char.charCodeAt(0);
  return (c >= 0x2e80 && c <= 0x303f) // radicals, kangxi, CJK punctuation
    || (c >= 0x3040 && c <= 0x30ff) // kana
    || (c >= 0x3400 && c <= 0x4dbf) // extension A
    || (c >= 0x4e00 && c <= 0x9fff) // unified ideographs
    || (c >= 0xf900 && c <= 0xfaff) // compatibility ideographs
    || (c >= 0xfe30 && c <= 0xfe4f) // vertical forms
    || (c >= 0xff00 && c <= 0xffef); // full-width forms
}

// ---------------------------------------------------------------------------
// Chapters
// ---------------------------------------------------------------------------

/** Java's `\s` (ASCII whitespace only: JavaScript's would take the ideographic space too). */
export const JAVA_SPACE = "[ \\t\\n\\x0B\\f\\r]";

const NUMERALS = "0-9０-９零〇一二三四五六七八九十百千万两";

/** `第一章`, `第 12 节`, `第三卷`: the marker most Chinese novels actually use. */
const CJK_HEADING = new RegExp(`^(?:正文[${JAVA_SPACE.slice(1, -1)}:：·　]*)?第${JAVA_SPACE}*[${NUMERALS}]{1,12}${JAVA_SPACE}*[章卷回节篇部集话](?:[${JAVA_SPACE.slice(1, -1)}:：.、·　\\-—]?[^\\n]{0,36})?$`);

/** The front and back matter of a novel, which is a heading with no number. */
const FRONT_MATTER = /^(?:序章|序言|楔子|引子|前言|序幕|尾声|终章|番外[0-9]{0,3}|后记|外传|附录).{0,36}$/;

const LATIN_HEADING = new RegExp(`^(?:Chapter|CHAPTER|chapter)${JAVA_SPACE}{0,2}[0-9]{1,4}[^\\n]{0,30}$`);

/**
 * Finds headings, best effort.
 *
 * Real files are unreliable about this: a 1.5 MB novel often carries only a handful of `第…章` lines, or none at all, so
 * this is a bonus index and never the primary navigation. [weak] adds "short line that looks like a title", which needs
 * the paragraphs to be real ones — call it after [reflow] — and is kept strict, because a heading list full of dialogue
 * is worse than a short one. A wrong entry only costs a bad row in the table of contents; nothing here changes what the
 * pages look like.
 */
export function findChapters(text: string, weak = true, limit = 2000): ChapterMark[] {
  const found: ChapterMark[] = [];
  let index = 0;
  let previousBlank = true;
  let previousSentence = true;
  let lastAccepted = -WEAK_GAP;
  while (index < text.length && found.length < limit) {
    const newline = text.indexOf("\n", index);
    const end = newline < 0 ? text.length : newline;
    let begin = index;
    let finish = end;
    while (begin < finish && isBlank(text[begin]!)) begin++;
    while (finish > begin && isBlank(text[finish - 1]!)) finish--;
    const length = finish - begin;
    if (length >= 2 && length <= 48) {
      const first = text[begin]!;
      let heading = false;
      if ("第正序楔引前尾终番后外附".includes(first)) heading = matchesAt(CJK_HEADING, text, begin, finish) || matchesAt(FRONT_MATTER, text, begin, finish);
      else if (first === "C" || first === "c") heading = matchesAt(LATIN_HEADING, text, begin, finish);
      if (heading) {
        found.push({ title: text.substring(begin, finish), offset: index });
        lastAccepted = index;
      } else if (weak && length >= 2 && length <= 20 && looksLikeTitle(text, begin, finish) && (previousBlank || previousSentence) && index - lastAccepted >= WEAK_GAP) {
        found.push({ title: text.substring(begin, finish), offset: index });
        lastAccepted = index;
      }
    }
    previousBlank = length === 0;
    previousSentence = length > 0 && (isBlank(text[finish - 1]!) || endsSentence(text[finish - 1]!));
    if (newline < 0) break;
    index = newline + 1;
  }
  return found;
}

/**
 * How far a title-like line has to sit from the previous entry.
 *
 * Without it, a chapter opening of three short unpunctuated lines becomes three table-of-contents rows.
 */
const WEAK_GAP = 200;

const matchesAt = (re: RegExp, text: string, start: number, end: number) => re.test(text.substring(start, end));

const isBlank = (char: string) => char === " " || char === "\t" || char === "　" || char === "﻿";

const endsSentence = (char: string) =>
  char === "。" || char === "！" || char === "？" || char === "…" || char === '"' || char === "”" ||
  char === "」" || char === "』" || char === ")" || char === "）";

/** A title-like line: no sentence punctuation, no brackets, nothing quoted. */
function looksLikeTitle(text: string, start: number, end: number): boolean {
  for (let position = start; position < end; position++) {
    if (TITLE_STOP_CHARS.includes(text[position]!)) return false;
  }
  return true;
}

const TITLE_STOP_CHARS = "。！？；，、：…—～·\"'“”‘’()（）[]【】《》〈〉「」『』";

// ---------------------------------------------------------------------------
// Chunking
// ---------------------------------------------------------------------------

/**
 * Cuts the text into contiguous blocks of at most [budget] characters.
 *
 * Blocks break at paragraph ends, so scrolling shows whole paragraphs and a page never starts mid-sentence for no
 * reason. A paragraph longer than the budget is the one exception — it has to be cut somewhere, and it is cut after
 * punctuation where there is any within reach, so the break at least looks like a break. [ChunkedText.starts] carries
 * where each block begins in the source, which is what chapter and search offsets are translated through.
 */
export function chunkText(text: string, budget: number = CHUNK_CHARS): ChunkedText {
  if (!(budget > 0)) throw new Error("budget must be positive");
  const chunks: string[] = [];
  const starts: number[] = [];
  let chunkStart = 0;
  let index = 0;
  while (index < text.length) {
    const newline = text.indexOf("\n", index);
    const end = newline < 0 ? text.length : newline + 1;
    if (chunkStart < index && end - chunkStart > budget) {
      chunks.push(text.substring(chunkStart, index));
      starts.push(chunkStart);
      chunkStart = index;
    }
    while (end - chunkStart > budget) {
      const cut = cutPoint(text, chunkStart, budget);
      chunks.push(text.substring(chunkStart, cut));
      starts.push(chunkStart);
      chunkStart = cut;
    }
    index = end;
  }
  if (chunkStart < text.length) {
    chunks.push(text.substring(chunkStart));
    starts.push(chunkStart);
  }
  return { chunks, starts };
}

/** Where to cut a paragraph that is longer than a block: at the last sentence end within reach, otherwise exactly at the budget. */
function cutPoint(text: string, start: number, budget: number): number {
  const target = Math.min(start + budget, text.length);
  const floor = Math.max(start + Math.trunc((budget * 3) / 4), start + 8);
  let position = target;
  while (position > floor) {
    if (CUT_CHARS.includes(text[position - 1]!)) return position;
    position--;
  }
  return target;
}

const CUT_CHARS = "。！？；…\n\"”」』";

/** The block that holds [offset], by binary search over the block starts. */
export function chunkIndexFor(starts: readonly number[], offset: number): number {
  if (starts.length === 0) return 0;
  let low = 0;
  let high = starts.length - 1;
  let answer = 0;
  while (low <= high) {
    const middle = (low + high) >> 1;
    if (starts[middle]! <= offset) {
      answer = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return answer;
}

// ---------------------------------------------------------------------------
// Rendering helpers
// ---------------------------------------------------------------------------

/** Spacing a file already put in front of a paragraph. */
const isLeadingSpace = (c: string) => c === " " || c === "\t" || c === "　";

/** How many characters of [chunk] from [start] up to [end] are leading spacing. */
function leadingSpace(chunk: string, start: number, end: number): number {
  let lead = 0;
  while (start + lead < end && isLeadingSpace(chunk[start + lead]!)) lead++;
  return lead;
}

/**
 * Whether a paragraph is a chapter heading by the strict rules alone (`第…章`, front and back matter, `Chapter N`).
 * Headings are not indented: an indented title reads as the first line of a paragraph.
 */
function isHeadingLine(chunk: string, begin: number, end: number): boolean {
  let finish = end;
  while (finish > begin && isBlank(chunk[finish - 1]!)) finish--;
  if (finish - begin < 2 || finish - begin > 48) return false;
  return matchesAt(CJK_HEADING, chunk, begin, finish) || matchesAt(FRONT_MATTER, chunk, begin, finish) || matchesAt(LATIN_HEADING, chunk, begin, finish);
}

/**
 * The text as it is laid out: paragraph indent is part of the string rather than a paragraph style, because a text has
 * no first-line indent (in Compose as in React Native) and a two-space prefix is how every Chinese e-book does it anyway.
 *
 * Most Chinese text files already start their paragraphs with two ideographic spaces, and adding ours on top indented
 * every paragraph by four. So whatever spacing a paragraph arrives with is replaced by the indent, not added to, and a
 * line that is nothing but spacing is drawn empty.
 */
export function renderChunk(chunk: string, indent: boolean): string {
  if (!indent) return chunk;
  const out: string[] = [];
  let index = 0;
  while (index < chunk.length) {
    const newline = chunk.indexOf("\n", index);
    const end = newline < 0 ? chunk.length : newline;
    const lead = leadingSpace(chunk, index, end);
    if (end > index + lead) {
      if (!isHeadingLine(chunk, index + lead, end)) out.push(INDENT);
      out.push(chunk.substring(index + lead, end));
    }
    if (newline < 0) break;
    out.push("\n");
    index = newline + 1;
  }
  return out.join("");
}

/**
 * Maps an offset in the raw block to the same position in [renderChunk]'s output: each paragraph before it gained an
 * indent and lost its own leading spacing. An offset inside that spacing lands where the paragraph's text starts.
 */
export function renderOffset(chunk: string, raw: number, indent: boolean): number {
  if (!indent || raw <= 0) return raw;
  let start = 0;
  let shift = 0;
  // `<=`: an offset at the very start of a paragraph belongs after that paragraph's indent, on its first character.
  while (start <= raw && start < chunk.length) {
    const newline = chunk.indexOf("\n", start);
    const end = newline < 0 ? chunk.length : newline;
    const lead = leadingSpace(chunk, start, end);
    const gained = end > start + lead && !isHeadingLine(chunk, start + lead, end) ? INDENT.length : 0;
    if (raw < start + lead) return start + shift + gained;
    shift += gained - lead;
    if (newline < 0) break;
    start = newline + 1;
  }
  return raw + shift;
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/**
 * Every occurrence of [query], over the raw blocks.
 *
 * Offsets are into the raw block, not into the indented text, so a result stays valid when the paragraph indent is
 * toggled; the caller maps them with [renderOffset]. Latin queries match case-insensitively as a second pass, only when
 * the first pass found nothing.
 */
export function searchChunks(chunks: readonly string[], query: string, limit = 400): TextMatch[] {
  if (query.length === 0) return [];
  const matches: TextMatch[] = [];
  for (let chunk = 0; chunk < chunks.length; chunk++) {
    const text = chunks[chunk]!;
    let from = 0;
    while (matches.length < limit) {
      const at = text.indexOf(query, from);
      if (at < 0) break;
      matches.push({ chunk, start: at, length: query.length });
      from = at + query.length;
    }
    if (matches.length >= limit) break;
  }
  if (matches.length > 0 || !/\p{L}/u.test(query)) return matches;
  const lowered = query.toLowerCase();
  // Folding can change a string's length in a handful of locales, and the offsets it reports would then be wrong; those
  // queries stay case sensitive.
  if (lowered.length !== query.length) return matches;
  for (let chunk = 0; chunk < chunks.length; chunk++) {
    const text = chunks[chunk]!;
    const folded = text.toLowerCase();
    if (folded.length !== text.length) continue;
    let from = 0;
    while (matches.length < limit) {
      const at = folded.indexOf(lowered, from);
      if (at < 0) break;
      matches.push({ chunk, start: at, length: query.length });
      from = at + query.length;
    }
    if (matches.length >= limit) break;
  }
  return matches;
}

/** The first match at or after a position, for "find the next one". */
export function firstMatchAfter(matches: readonly TextMatch[], chunk: number, offset: number): number {
  const at = matches.findIndex((it) => it.chunk > chunk || (it.chunk === chunk && it.start >= offset));
  return at >= 0 ? at : 0;
}
