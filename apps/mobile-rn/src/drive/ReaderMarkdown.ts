// A block of Markdown as the reader draws it (drive/ReaderMarkdown.kt). Compose's AnnotatedString is here a text and
// the styles over its ranges (`Styled`), which the reader draws as nested Text (Reader.tsx `StyledText`).
import { JAVA_SPACE } from "./TextModel";
import type { ChapterMark } from "./TextModel";

/** A style over a range of a text (Compose's SpanStyle): what is set wins over what is under it. */
export interface SpanStyle {
  color?: string;
  fontWeight?: "600";
  fontStyle?: "italic";
  fontFamily?: string;
  fontSize?: number;
  textDecorationLine?: "line-through" | "underline";
  backgroundColor?: string;
}

/** A text with styles over ranges of it (Compose's AnnotatedString); later styles over earlier ones. */
export interface Styled { text: string; spans: { start: number; end: number; style: SpanStyle }[] }

/** A text's pieces, each with all the styles over it merged in order: what draws it. */
export function piecesOf(s: Styled): { text: string; style: SpanStyle }[] {
  if (s.spans.length === 0) return [{ text: s.text, style: {} }];
  const cuts = new Set<number>([0, s.text.length]);
  for (const sp of s.spans) { cuts.add(Math.max(0, Math.min(s.text.length, sp.start))); cuts.add(Math.max(0, Math.min(s.text.length, sp.end))); }
  const at = [...cuts].sort((a, b) => a - b);
  const out: { text: string; style: SpanStyle }[] = [];
  for (let k = 0; k + 1 < at.length; k++) {
    const from = at[k]!;
    const to = at[k + 1]!;
    if (to <= from) continue;
    let style: SpanStyle = {};
    for (const sp of s.spans) if (sp.start <= from && sp.end >= to) style = merge(style, sp.style);
    out.push({ text: s.text.substring(from, to), style });
  }
  return out;
}

/** The colours a Markdown page needs on top of the body text. */
export interface MarkdownColors { muted: string; accent: string; code: string }

/**
 * One chunk of Markdown, drawn.
 *
 * [rawIndexOf] is what makes search and "jump to here" work in a file whose syntax is not shown: character *n* of
 * [styled] came from character `rawIndexOf[n]` of the file, so a hit found in the raw text can be highlighted where it
 * ended up on screen.
 */
export class MarkdownChunk {
  constructor(
    readonly styled: Styled,
    private readonly rawIndexOf: readonly number[],
    /** Space to leave above this block, which is how headings get their air. */
    readonly leadingDp: number,
  ) {}

  get length(): number { return this.styled.text.length; }

  /** Where a raw offset lands in what is drawn. */
  renderedIndex(raw: number): number {
    const map = this.rawIndexOf;
    if (map.length === 0) return 0;
    if (raw >= map[map.length - 1]!) return map.length;
    let low = 0;
    let high = map.length - 1;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (map[mid]! < raw) low = mid + 1; else high = mid;
    }
    return low;
  }
}

const BULLET = "• ";
const QUOTE_BAR = "▎ ";
const RULE = "─";

/** Kotlin's Char.isWhitespace: Java's whitespace and the Unicode space separators. */
const isWhitespace = (c: string) => /[\t\n\u000B\f\r\u001C-\u001F\p{Zs}\p{Zl}\p{Zp}]/u.test(c);
const trimStart = (s: string) => { let i = 0; while (i < s.length && isWhitespace(s[i]!)) i++; return s.substring(i); };
const trim = (s: string) => { let i = 0; let j = s.length; while (i < j && isWhitespace(s[i]!)) i++; while (j > i && isWhitespace(s[j - 1]!)) j--; return s.substring(i, j); };
const isBlankLine = (s: string) => trim(s).length === 0;

/**
 * Draws one block of Markdown.
 *
 * Deliberately small: headings, quotes, lists, rules, fenced code, and the inline forms that turn up in prose — bold,
 * italic, strikethrough, code and links. Tables, images and nested lists are not rendered; a novel is prose, and a
 * parser that tries to be a browser is one that breaks on a stray asterisk.
 */
export function renderMarkdown(chunk: string, bodySp: number, colors: MarkdownColors): MarkdownChunk {
  let text = "";
  const spans: Styled["spans"] = [];
  const map: number[] = [];
  const muted: SpanStyle = { color: colors.muted };
  const code: SpanStyle = { fontFamily: "monospace", color: colors.code };
  const addStyle = (style: SpanStyle, start: number, end: number) => { if (end > start) spans.push({ start, end, style }); };

  /**
   * Appends what will be drawn for a raw span, keeping the map one entry per drawn character.
   *
   * The two lengths differ wherever a marker becomes a glyph — `- ` becomes `• `, `> ` becomes `▎ `, `---` becomes a
   * rule — and the map has to stay exactly as long as the text or every later offset is wrong. That is what put search
   * highlights on the wrong words.
   */
  const put = (piece: string, rawFrom: number, rawTo: number, style: SpanStyle | null) => {
    if (piece.length === 0) return;
    const start = text.length;
    text += piece;
    if (style !== null) addStyle(style, start, text.length);
    const span = Math.max(1, rawTo - rawFrom);
    for (let i = 0; i < piece.length; i++) map.push(rawFrom + Math.trunc((i * span) / piece.length));
  };

  const putOne = (rawIndex: number, style: SpanStyle | null, ch: string = chunk[rawIndex]!) => {
    const start = text.length;
    text += ch;
    if (style !== null) addStyle(style, start, text.length);
    map.push(rawIndex);
  };

  /** The inline forms, longest marker first so `**` is not read as two `*`. */
  const inline = (base: number, s: string, style: SpanStyle | null): void => {
    let i = 0;
    while (i < s.length) {
      const at = base + i;
      if (s[i] === "\\" && i + 1 < s.length) {
        putOne(at + 1, style);
        i += 2;
      } else if (s.startsWith("**", i) || s.startsWith("__", i)) {
        const marker = s.substring(i, i + 2);
        const close = s.indexOf(marker, i + 2);
        if (close > i + 2) {
          inline(base + i + 2, s.substring(i + 2, close), bold(style));
          i = close + 2;
        } else { putOne(at, style); i++; }
      } else if (s.startsWith("~~", i)) {
        const close = s.indexOf("~~", i + 2);
        if (close > i + 2) {
          inline(base + i + 2, s.substring(i + 2, close), { ...(style ?? {}), textDecorationLine: "line-through" });
          i = close + 2;
        } else { putOne(at, style); i++; }
      } else if (s[i] === "`") {
        const close = s.indexOf("`", i + 1);
        if (close > i) {
          inline(base + i + 1, s.substring(i + 1, close), merge(style, code));
          i = close + 1;
        } else { putOne(at, style); i++; }
      } else if (s[i] === "*" || s[i] === "_") {
        const marker = s[i]!;
        const close = s.indexOf(marker, i + 1);
        if (close > i + 1) {
          inline(base + i + 1, s.substring(i + 1, close), merge(style, { fontStyle: "italic" }));
          i = close + 1;
        } else { putOne(at, style); i++; }
      } else if (s[i] === "[") {
        const mid = s.indexOf("](", i);
        const close = mid < 0 ? -1 : s.indexOf(")", mid + 2);
        if (mid > i && close > mid) {
          // The label is what a reader needs; the address is not something a phone reader can follow usefully here.
          inline(base + i + 1, s.substring(i + 1, mid), merge(style, { color: colors.accent, textDecorationLine: "underline" }));
          i = close + 1;
        } else { putOne(at, style); i++; }
      } else {
        putOne(at, style); i++;
      }
    }
  };

  const lines = chunk.split("\n");
  let at = 0;
  let fenced = false;
  let leading: number | null = null;

  for (let number = 0; number < lines.length; number++) {
    const line = lines[number]!;
    const lineStart = at;
    at += line.length + 1;

    const fence = trimStart(line).startsWith("```") || trimStart(line).startsWith("~~~");
    if (fence) {
      fenced = !fenced;
      if (leading === null) leading = 4;
      if (number < lines.length - 1) putOne(lineStart + line.length, null, "\n");
      continue;
    }
    if (fenced) {
      put(line, lineStart, lineStart + line.length, code);
      if (number < lines.length - 1) putOne(lineStart + line.length, null, "\n");
      continue;
    }

    const heading = HEADING.exec(line);
    const rule = RULE_LINE.test(trim(line));
    const quote = QUOTE.exec(line);
    const bullet = BULLET_ITEM.exec(line);
    const ordered = ORDERED_ITEM.exec(line);

    if (heading !== null) {
      const level = heading[1]!.length;
      const scale = level === 1 ? 1.55 : level === 2 ? 1.34 : level === 3 ? 1.18 : 1.08;
      if (leading === null) leading = level <= 2 ? 16 : 8;
      const body = trim(heading[2]!);
      const start = text.length;
      inline(lineStart + Math.max(0, line.indexOf(body)), body, { fontWeight: "600" });
      addStyle({ fontSize: bodySp * scale, fontWeight: "600" }, start, text.length);
    } else if (rule) {
      if (leading === null) leading = 14;
      const start = text.length;
      put(RULE.repeat(18), lineStart, lineStart + line.length, muted);
      addStyle(muted, start, text.length);
    } else if (quote !== null) {
      if (leading === null) leading = 6;
      put(QUOTE_BAR, lineStart, lineStart + 1, { color: colors.accent });
      const body = quote[1]!;
      inline(lineStart + Math.max(0, line.indexOf(body)), body, muted);
    } else if (bullet !== null) {
      if (leading === null) leading = 2;
      put(BULLET, lineStart, lineStart + bullet[1]!.length, muted);
      const body = bullet[2]!;
      inline(lineStart + Math.max(0, line.indexOf(body)), body, null);
    } else if (ordered !== null) {
      if (leading === null) leading = 2;
      const marker = ordered[1]!;
      put(`${marker} `, lineStart, lineStart + marker.length, muted);
      const body = ordered[3]!;
      inline(lineStart + Math.max(0, line.indexOf(body)), body, null);
    } else if (isBlankLine(line)) {
      if (number < lines.length - 1) putOne(lineStart, null, "\n");
    } else {
      inline(lineStart, line, null);
    }

    if (number < lines.length - 1 && !isBlankLine(line) && !fence) {
      putOne(lineStart + line.length, null, "\n");
    }
  }

  return new MarkdownChunk({ text, spans }, map, leading ?? 0);
}

// Java's `\s` and `.` as Kotlin's Regex has them (JAVA_SPACE: ASCII whitespace only).
const S = JAVA_SPACE;
const HEADING = new RegExp(`^(#{1,6})${S}+(.*?)${S}*#*${S}*$`);
const RULE_LINE = /^(-{3,}|\*{3,}|_{3,})$/;
const QUOTE = new RegExp(`^>${S}?(.*)$`);
const BULLET_ITEM = new RegExp(`^${S}*([-*+])${S}+(.*)$`);
const ORDERED_ITEM = new RegExp(`^${S}*([0-9]{1,3}([.)]))${S}+(.*)$`);

const bold = (style: SpanStyle | null): SpanStyle => ({ ...(style ?? {}), fontWeight: "600" });

/** Compose's SpanStyle.merge: what `extra` sets over what `style` has. */
function merge(style: SpanStyle | null, extra: SpanStyle): SpanStyle {
  const out: SpanStyle = { ...(style ?? {}) };
  for (const [k, v] of Object.entries(extra)) if (v !== undefined) (out as Record<string, unknown>)[k] = v;
  return out;
}

/**
 * Heading lines as a table of contents.
 *
 * Markdown says where its sections begin, so this does not have to guess the way the plain-text hunt does: `#` to `###`
 * is a chapter, deeper is a subtitle and is left out of the list.
 */
export function markdownChapters(text: string, maxLevel = 3, limit = 2000): ChapterMark[] {
  const marks: ChapterMark[] = [];
  let at = 0;
  let fenced = false;
  for (const line of text.split("\n")) {
    const start = at;
    at += line.length + 1;
    if (trimStart(line).startsWith("```") || trimStart(line).startsWith("~~~")) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    const heading = HEADING.exec(line);
    if (heading === null) continue;
    if (heading[1]!.length > maxLevel) continue;
    const title = trim(heading[2]!);
    if (title.length === 0) continue;
    marks.push({ title, offset: start });
    if (marks.length >= limit) break;
  }
  return marks;
}
