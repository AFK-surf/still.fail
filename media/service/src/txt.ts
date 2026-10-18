// A plain-text book: its encoding found (UTF-8, UTF-16 by its BOM, else GB18030), one paragraph per line, chapters
// where a line is a heading (第…章/回/节/卷, Chapter N), else parts of about 20 000 characters split between paragraphs.
import type { Block, Chapter, Parsed } from "./blocks.ts";
import { MediaError } from "./errors.ts";

/// The text of `b`: by its BOM (UTF-8, UTF-16 LE or BE), else UTF-8 when it is valid UTF-8, else GB18030 (which GBK
/// and GB2312 are part of).
export function decodeText(b: Uint8Array): string {
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return new TextDecoder("utf-8").decode(b.subarray(3));
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder("utf-16le").decode(b.subarray(2));
  if (b[0] === 0xfe && b[1] === 0xff) return new TextDecoder("utf-16be").decode(b.subarray(2));
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(b);
  } catch {
    return new TextDecoder("gb18030").decode(b);
  }
}

/// Whether the start of `b` looks like text (no NUL bytes outside UTF-16).
export function looksLikeText(b: Uint8Array): boolean {
  if ((b[0] === 0xff && b[1] === 0xfe) || (b[0] === 0xfe && b[1] === 0xff)) return true;
  return !b.subarray(0, 4096).includes(0);
}

const NUM = "0-9０-９零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟";
/// A chapter's heading: 第…章 (回, 节, 集, 话), or a volume's: 第…卷 (部, 篇); with a title after it or not.
const CHAPTER = new RegExp(`^第[${NUM}]+[章回节集话](?:[\\s:：.、·—-].*|$)`);
const VOLUME = new RegExp(`^第[${NUM}]+[卷部篇](?:[\\s:：.、·—-].*|$)`);
const ENGLISH = /^chapter\s+(?:[0-9]+|[ivxlcdm]+)\b(?:[\s:.\-—].*|$)/i;
const SPECIAL = /^(?:序章|序言|楔子|引子|尾声|后记)(?:[\s:：].*)?$/;

type Heading = { title: string; volume: boolean };

/// The heading `line` is (a short line of one of the forms above), or null.
export function headingOf(line: string): Heading | null {
  if (line.length > 50) return null;
  if (VOLUME.test(line)) return { title: line, volume: true };
  if (CHAPTER.test(line) || SPECIAL.test(line) || (line.length <= 80 && ENGLISH.test(line))) return { title: line, volume: false };
  return null;
}

const PART = 20_000;

/// The book `text` is; `name` is its file's name, which titles it.
export function parseTxt(text: string, name: string): Parsed {
  const lines = text
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((l) => l.replace(/^[\s　 ﻿]+|[\s　 ]+$/g, "").replace(/[ \t]+/g, " "))
    .filter((l) => l.length > 0);

  type Raw = { heading: Heading | null; paragraphs: string[] };
  const raws: Raw[] = [{ heading: null, paragraphs: [] }];
  for (const line of lines) {
    const h = headingOf(line);
    if (h) raws.push({ heading: h, paragraphs: [] });
    else raws[raws.length - 1]!.paragraphs.push(line);
  }
  // A chapter heading with nothing under it, right before another heading, is a list of the chapters at the top of
  // the file, not a chapter (a volume's heading is kept: its chapters follow it).
  const kept = raws.filter((r, i) => (r.heading === null ? r.paragraphs.length > 0 : r.heading.volume || r.paragraphs.length > 0 || i === raws.length - 1));
  const headings = kept.filter((r) => r.heading !== null);
  const volumes = headings.some((r) => r.heading!.volume) && headings.some((r) => !r.heading!.volume);

  const chapters: Chapter[] = [];
  if (headings.length === 0) {
    // No headings: parts of about PART characters, each ending at a paragraph's end.
    let blocks: Block[] = [];
    let chars = 0;
    for (const p of kept[0]?.paragraphs ?? []) {
      blocks.push({ t: "p", text: p });
      chars += p.length;
      if (chars >= PART) {
        chapters.push({ title: `第 ${chapters.length + 1} 部分`, level: 1, blocks });
        blocks = [];
        chars = 0;
      }
    }
    if (blocks.length > 0) chapters.push({ title: `第 ${chapters.length + 1} 部分`, level: 1, blocks });
  } else {
    for (const r of kept) {
      const blocks: Block[] = r.paragraphs.map((text) => ({ t: "p", text }));
      if (r.heading === null) {
        chapters.push({ title: "前言", level: 1, blocks });
        continue;
      }
      const level = volumes && !r.heading.volume ? 2 : 1;
      chapters.push({ title: r.heading.title, level, blocks: [{ t: "h", level, text: r.heading.title }, ...blocks] });
    }
  }
  if (chapters.length === 0) throw new MediaError("bad_request", "这个文本文件是空的");

  const author = lines.slice(0, 30).map((l) => /^作者[:：]\s*(.+)$/.exec(l)?.[1]).find((a) => a !== undefined) ?? "";
  const title = name.replace(/\.[^.]+$/, "").replace(/^《(.+?)》.*$/, "$1").trim() || name;
  return { title, author: author.trim(), format: "txt", cover: null, chapters, images: new Map() };
}
