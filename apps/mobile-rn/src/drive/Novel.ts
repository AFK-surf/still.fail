// A text file of a drive made ready to read (drive/Novel.kt, zdrive's Novel.kt): fetched whole through the core
// (drive.read, a part at a time), decoded (UTF-8, else GB18030), a hard-wrapped novel reflowed into paragraphs, its
// chapters found, and cut into blocks a list lays out one at a time. Where the reader is, is an offset into the text it
// shows (drivePlace's `at`).
import { Platform, type TextStyle } from "react-native";
import type { ReaderPrefs } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";
import { Dark, Light } from "../ui/Theme";
import { markdownChapters } from "./ReaderMarkdown";
import { chunkIndexFor, chunkText, decodeText, detectWrapWidth, findChapters, normaliseLineEndings, reflow, type NovelChapter } from "./TextModel";

/**
 * A text, ready to show in pieces: [chunks] are contiguous blocks of the text shown (each starts at [starts] of it), a
 * list virtualises them; [length] is the whole text's. [bytes] were read of [sourceBytes] (fewer when cut at
 * [MAX_NOVEL_BYTES]).
 */
export class Novel {
  constructor(
    readonly title: string,
    readonly chunks: string[],
    readonly starts: number[],
    readonly length: number,
    readonly charCount: number,
    readonly bytes: number,
    readonly chapters: NovelChapter[],
    readonly encoding: string,
    readonly sourceBytes: number,
    readonly truncated: boolean,
    /** Drawn as Markdown, not as its source (`.md`). */
    readonly markdown: boolean,
  ) {}

  /** The block an offset of the text is in, and how far into it. */
  at(offset: number): [number, number] {
    if (this.chunks.length === 0) return [0, 0];
    const i = chunkIndexFor(this.starts, Math.min(Math.max(offset, 0), this.length));
    return [i, Math.min(Math.max(offset - this.starts[i]!, 0), this.chunks[i]!.length)];
  }

  /** The offset of the text a block and a share of it is at. */
  offsetOf(chunk: number, within: number): number {
    const c = Math.min(Math.max(chunk, 0), Math.max(this.chunks.length - 1, 0));
    return Math.min(Math.max((this.starts[c] ?? 0) + Math.trunc((this.chunks[c] ?? "").length * within), 0), this.length);
  }
}

/**
 * The most of a text the reader holds: the bytes, the decoded text (two bytes a character) and its blocks are all in
 * memory at once, about four times the file at the peak. A bigger file opens with its first 16 MB and says so.
 */
export const MAX_NOVEL_BYTES = 16 * 1024 * 1024;

/**
 * Decoding and indexing, on bytes already in memory. Headings are found twice: before the reflow, so a heading line is
 * not welded into the paragraph above it, and after it, where lines really are paragraphs.
 */
export function buildNovel(name: string, bytes: Uint8Array, size: number, truncated: boolean): Novel {
  const decoded = decodeText(bytes, 0, bytes.length, truncated);
  const normalised = normaliseLineEndings(decoded.text);
  const lower = name.toLowerCase();
  const markdown = lower.endsWith(".md") || lower.endsWith(".markdown");
  // Markdown is laid out line by line already: reflowing it would weld a heading into the paragraph under it.
  const wrap = markdown ? 0 : detectWrapWidth(normalised);
  const protectedHeadings = wrap > 0 ? findChapters(normalised, false) : [];
  const text = wrap > 0 ? reflow(normalised, wrap, new Set(protectedHeadings.map((it) => it.offset))) : normalised;
  const chunked = chunkText(text);
  const chapters = (markdown ? markdownChapters(text) : findChapters(text)).map((mark) => {
    const chunk = chunkIndexFor(chunked.starts, mark.offset);
    return { title: mark.title, chunk, offset: mark.offset - chunked.starts[chunk]! };
  });
  return new Novel(name, chunked.chunks, chunked.starts, text.length, decoded.text.length, bytes.length, chapters, decoded.encoding, Math.max(size, 0), truncated, markdown);
}

// ── how it is drawn ─────────────────────────────────────────────────────

/** What a page of the reader is drawn on: its ground, its text, what is quieter, the bars floating over it. */
export interface PaperInk { ground: string; ink: string; muted: string; bar: string; accent: string; dark: boolean }

/**
 * The papers a reader can pick (zdrive's), in still.fail's colours: the app's own light and dark page, a green and a
 * grey one; `Follow` (the default) is the app's light or dark as it is now. Kept by the core (`prefs.reader.paper`).
 */
export class Paper {
  private constructor(readonly key: string, readonly ordinal: number) {}

  static readonly Follow = new Paper("follow", 0);
  static readonly White = new Paper("white", 1);
  static readonly Green = new Paper("green", 2);
  static readonly Grey = new Paper("grey", 3);
  static readonly Night = new Paper("night", 4);
  static readonly entries: readonly Paper[] = [Paper.Follow, Paper.White, Paper.Green, Paper.Grey, Paper.Night];

  get label(): string { return t(`android-misc.drive.reader.paper.${this.key}`); }

  ink(appDark: boolean): PaperInk {
    switch (this) {
      case Paper.Follow: return (appDark ? Paper.Night : Paper.White).ink(appDark);
      case Paper.White: return { ground: Light.bg, ink: Light.ink, muted: Light.muted, bar: "#FFFFFF", accent: Light.accent, dark: false };
      case Paper.Green: return { ground: "#E4ECDB", ink: "#24301F", muted: "#58654F", bar: "#F4F7EF", accent: Light.accent, dark: false };
      case Paper.Grey: return { ground: "#ECECEC", ink: Light.ink, muted: "#66686C", bar: "#F8F8F8", accent: Light.accent, dark: false };
      default: return { ground: Dark.bg, ink: Dark.ink, muted: Dark.muted, bar: "#2A2C31", accent: Dark.accent, dark: true };
    }
  }

  static of(key: string | null | undefined): Paper {
    return Paper.entries.find((it) => it.key === key) ?? Paper.Follow;
  }
}

/** The system's serif and sans faces (Compose's FontFamily.Serif and SansSerif). */
const SERIF = Platform.select({ android: "serif", ios: "Times New Roman", default: "serif" });
const SANS = Platform.select({ android: "sans-serif", ios: "System", default: "sans-serif" });

/** The two faces a phone reader offers (`prefs.reader.face`). */
export class ReaderFamily {
  private constructor(readonly key: string, readonly family: string, readonly ordinal: number) {}

  static readonly Serif = new ReaderFamily("serif", SERIF, 0);
  static readonly Sans = new ReaderFamily("sans", SANS, 1);
  static readonly entries: readonly ReaderFamily[] = [ReaderFamily.Serif, ReaderFamily.Sans];

  get label(): string { return t(`android-misc.drive.reader.font.${this.key}`); }

  static of(key: string | null | undefined): ReaderFamily {
    return ReaderFamily.entries.find((it) => it.key === key) ?? ReaderFamily.Serif;
  }
}

/** Everything the reader lays text out with, as the core keeps it (`prefs.reader`): the sheet changes it, the page is drawn with it. */
export class ReaderTypography {
  constructor(readonly fontSp: number, readonly lineSpacing: number, readonly marginDp: number, readonly family: ReaderFamily, readonly indent: boolean) {}

  style(color: string): TextStyle {
    return { color, fontSize: this.fontSp, lineHeight: this.fontSp * this.lineSpacing, fontFamily: this.family.family, textAlign: "left", letterSpacing: 0, includeFontPadding: false };
  }

  /** Each setting's range (the core keeps them within it): where the sheet's steps stop. */
  static readonly MIN_FONT_SP = 12;
  static readonly MAX_FONT_SP = 32;
  static readonly MIN_LINE_SPACING = 1.2;
  static readonly MAX_LINE_SPACING = 2.4;
  static readonly MIN_MARGIN_DP = 8;
  static readonly MAX_MARGIN_DP = 44;

  static of(p: ReaderPrefs): ReaderTypography {
    return new ReaderTypography(Math.trunc(p.size), p.line, Math.trunc(p.margin), ReaderFamily.of(p.face), p.indent);
  }

  /** The same as `other` (Compose's data class equality, which remembers key on). */
  key(): string { return `${this.fontSp}|${this.lineSpacing}|${this.marginDp}|${this.family.key}|${this.indent}`; }
}

/**
 * Where a jump lands: a block and an offset in it; `serial` makes the same place asked twice two jumps; `lead`: a little of
 * what is before it shown too (not when going back to where the reader was).
 */
export interface ReaderJump { chunk: number; offset: number; serial: number; lead: boolean }
