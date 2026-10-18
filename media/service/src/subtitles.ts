// Subtitles beside a video (`name.srt`, `name.zh.srt`, `name.chs.ass`, `.ssa`, `.vtt`) found by their names, and turned
// into WebVTT here (no ffmpeg): SubRip's cues, ASS/SSA's Dialogue lines (their styling tags taken off), WebVTT as it is.
// The text's encoding found as a TXT book's is (UTF-8, UTF-16 by BOM, else GB18030).
import { decodeText } from "./txt.ts";
import { stemOf } from "./videoname.ts";

export type SubFormat = "srt" | "ass" | "ssa" | "vtt";
export const SUB_EXTS = new Set<SubFormat>(["srt", "ass", "ssa", "vtt"]);

/// An external subtitle of a video: its file's name (in the video's folder), its format, the language and title its
/// name gives, whether it says it is forced.
export type ExternalSub = { name: string; format: SubFormat; lang: string | null; title: string | null; forced: boolean };

/// What a tag in a subtitle's name says: a language (BCP 47-ish) and how to call it.
const LANGS: Record<string, [string, string]> = {
  zh: ["zh", "中文"], chi: ["zh", "中文"], zho: ["zh", "中文"], chinese: ["zh", "中文"], 中文: ["zh", "中文"], 中字: ["zh", "中文"],
  chs: ["zh-Hans", "简体中文"], sc: ["zh-Hans", "简体中文"], gb: ["zh-Hans", "简体中文"], "zh-cn": ["zh-Hans", "简体中文"], "zh-hans": ["zh-Hans", "简体中文"], zhs: ["zh-Hans", "简体中文"], 简体: ["zh-Hans", "简体中文"], 简中: ["zh-Hans", "简体中文"], 简: ["zh-Hans", "简体中文"],
  cht: ["zh-Hant", "繁體中文"], tc: ["zh-Hant", "繁體中文"], big5: ["zh-Hant", "繁體中文"], "zh-tw": ["zh-Hant", "繁體中文"], "zh-hk": ["zh-Hant", "繁體中文"], "zh-hant": ["zh-Hant", "繁體中文"], zht: ["zh-Hant", "繁體中文"], 繁体: ["zh-Hant", "繁體中文"], 繁體: ["zh-Hant", "繁體中文"], 繁中: ["zh-Hant", "繁體中文"], 繁: ["zh-Hant", "繁體中文"],
  "chs&eng": ["zh-Hans", "简体中文 / English"], "cht&eng": ["zh-Hant", "繁體中文 / English"], 简英: ["zh-Hans", "简体中文 / English"], 繁英: ["zh-Hant", "繁體中文 / English"], 中英: ["zh", "中文 / English"], 双语: ["zh", "中文 / English"],
  en: ["en", "English"], eng: ["en", "English"], english: ["en", "English"], 英文: ["en", "English"], 英: ["en", "English"],
  ja: ["ja", "日本語"], jp: ["ja", "日本語"], jpn: ["ja", "日本語"], japanese: ["ja", "日本語"], 日文: ["ja", "日本語"],
  ko: ["ko", "한국어"], kor: ["ko", "한국어"], korean: ["ko", "한국어"], 韩文: ["ko", "한국어"],
  fr: ["fr", "Français"], fre: ["fr", "Français"], fra: ["fr", "Français"], de: ["de", "Deutsch"], ger: ["de", "Deutsch"], deu: ["de", "Deutsch"],
  es: ["es", "Español"], spa: ["es", "Español"], it: ["it", "Italiano"], ita: ["it", "Italiano"], ru: ["ru", "Русский"], rus: ["ru", "Русский"],
  pt: ["pt", "Português"], por: ["pt", "Português"],
};

/// The subtitles among a folder's file names that belong to the video `video` (same stem, or the stem and tags:
/// `Movie.zh.srt`, `Movie.chs.forced.ass`); the ones with a language first as found.
export function subtitlesOf(video: string, names: string[]): ExternalSub[] {
  const stem = stemOf(video);
  const out: ExternalSub[] = [];
  for (const name of names) {
    const dot = name.lastIndexOf(".");
    const ext = name.slice(dot + 1).toLowerCase() as SubFormat;
    if (dot <= 0 || !SUB_EXTS.has(ext)) continue;
    const base = name.slice(0, dot);
    if (base !== stem && !base.startsWith(`${stem}.`)) continue;
    const tags = base === stem ? [] : base.slice(stem.length + 1).split(".").map((t) => t.trim().toLowerCase()).filter((t) => t !== "");
    let lang: string | null = null;
    let title: string | null = null;
    let forced = false;
    for (const t of tags) {
      if (t === "forced") forced = true;
      else if (t === "default" || t === "sdh" || t === "cc") continue;
      else if (LANGS[t] && !lang) [lang, title] = LANGS[t]!;
      else if (!title) title = t;
    }
    out.push({ name, format: ext, lang, title, forced });
  }
  return out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

const pad = (n: number, w = 2) => String(n).padStart(w, "0");
const vttTime = (ms: number) => {
  const t = Math.max(0, Math.round(ms));
  return `${pad(Math.floor(t / 3_600_000))}:${pad(Math.floor(t / 60_000) % 60)}:${pad(Math.floor(t / 1000) % 60)}.${pad(t % 1000, 3)}`;
};

/// `<` `>` `&` made safe in a cue's text; the tags WebVTT knows (b, i, u) kept.
const cueText = (s: string) =>
  s
    .replace(/&(?![a-z]+;|#\d+;)/gi, "&amp;")
    .replace(/<(?!\/?(?:b|i|u)>)/gi, "&lt;")
    .replace(/(?<!<\/?(?:b|i|u))>/gi, "&gt;");

/// A subtitle file's bytes as WebVTT text.
export function toVtt(bytes: Uint8Array, format: SubFormat): string {
  const text = decodeText(bytes).replace(/\r\n?/g, "\n").replace(/^﻿/, "");
  if (format === "vtt") return /^WEBVTT/.test(text) ? (text.endsWith("\n") ? text : `${text}\n`) : `WEBVTT\n\n${text}`;
  if (format === "srt") return srtToVtt(text);
  return assToVtt(text);
}

/// SubRip: blocks of an index, `00:00:01,000 --> 00:00:02,500`, lines of text; <font> and {\an8} taken off.
export function srtToVtt(text: string): string {
  const cues: string[] = [];
  const time = /(\d{1,3}):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?/;
  const ms = (m: RegExpExecArray) => ((Number(m[1]) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000 + Number((m[4] ?? "0").padEnd(3, "0"));
  for (const block of text.split(/\n\s*\n/)) {
    const lines = block.split("\n").filter((l, i, all) => !(i === 0 && /^\s*\d+\s*$/.test(l) && all.length > 1 && all[1]!.includes("-->")));
    const at = lines.findIndex((l) => l.includes("-->"));
    if (at < 0) continue;
    const [from, to] = lines[at]!.split("-->");
    const a = time.exec(from ?? "");
    const b = time.exec(to ?? "");
    if (!a || !b) continue;
    const body = lines
      .slice(at + 1)
      .map((l) => cueText(l.replace(/<\/?font[^>]*>/gi, "").replace(/\{\\[^}]*\}/g, "").trim()))
      .filter((l) => l !== "");
    if (body.length === 0) continue;
    cues.push(`${vttTime(ms(a))} --> ${vttTime(ms(b))}\n${body.join("\n")}`);
  }
  return `WEBVTT\n\n${cues.join("\n\n")}${cues.length ? "\n" : ""}`;
}

/// ASS / SSA: the [Events] section's Format and Dialogue lines, in the order of their start; override tags
/// ({\pos(…)}, {\fad…}) taken off, \N and \n made lines, \h a space; drawings (\p1) left out.
export function assToVtt(text: string): string {
  let inEvents = false;
  let format: string[] = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"];
  const cues: { start: number; end: number; text: string; order: number }[] = [];
  const time = (s: string) => {
    const m = /^\s*(\d+):(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?/.exec(s);
    if (!m) return null;
    const frac = m[4] ?? "0";
    return ((Number(m[1]) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000 + Math.round(Number(`0.${frac}`) * 1000);
  };
  for (const line of text.split("\n")) {
    const l = line.trim();
    if (/^\[.*\]$/.test(l)) {
      inEvents = l.toLowerCase() === "[events]";
      continue;
    }
    if (!inEvents) continue;
    const colon = l.indexOf(":");
    if (colon < 0) continue;
    const key = l.slice(0, colon).trim().toLowerCase();
    const rest = l.slice(colon + 1).trimStart();
    if (key === "format") {
      format = rest.split(",").map((f) => f.trim().toLowerCase());
      continue;
    }
    if (key !== "dialogue") continue;
    // The text is the last field and may have commas.
    const parts = rest.split(",");
    const fields = [...parts.slice(0, format.length - 1), parts.slice(format.length - 1).join(",")];
    const get = (f: string) => fields[format.indexOf(f)] ?? "";
    const start = time(get("start"));
    const end = time(get("end"));
    if (start === null || end === null || end <= start) continue;
    let raw = get("text");
    if (/\{[^}]*\\p[1-9]/.test(raw)) continue;
    raw = raw
      .replace(/\{[^}]*\}/g, "")
      .replace(/\\[Nn]/g, "\n")
      .replace(/\\h/g, " ");
    const body = raw
      .split("\n")
      .map((x) => cueText(x.trim()))
      .filter((x) => x !== "")
      .join("\n");
    if (body) cues.push({ start, end, text: body, order: cues.length });
  }
  cues.sort((a, b) => a.start - b.start || a.order - b.order);
  return `WEBVTT\n\n${cues.map((c) => `${vttTime(c.start)} --> ${vttTime(c.end)}\n${c.text}`).join("\n\n")}${cues.length ? "\n" : ""}`;
}
