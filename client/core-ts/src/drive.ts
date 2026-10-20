// A folder of a station's drive as the clients show it (the `drive` topic; docs/drive.md): each entry with what kind it
// is (which viewer opens it, which mark it has), its size and time in words, and the folder's count in a line.
import { bytes, clock, local, localDay } from "./format.ts";
import { current, tr } from "./i18n.ts";
import type { Clock } from "./present.ts";
import { get, isObject } from "./util.ts";

type J = any;

/// What opens an entry: a folder is entered, video and audio play, text and Markdown are read, the rest is previewed
/// as chat attachments are (image, pdf, code, csv, html) or handed to the system (other).
export type DriveKind = "folder" | "video" | "audio" | "image" | "markdown" | "text" | "code" | "csv" | "html" | "pdf" | "subtitle" | "other";

const EXT: Record<string, DriveKind> = {};
const put = (kind: DriveKind, exts: string) => exts.split(" ").forEach((e) => (EXT[e] = kind));
put("video", "mp4 m4v mov webm mkv avi ts m2ts flv wmv 3gp");
put("audio", "mp3 m4a aac flac wav ogg opus wma");
put("image", "png jpg jpeg gif webp svg heic bmp avif");
put("markdown", "md markdown");
put("text", "txt log text");
put("code", "js mjs cjs ts tsx jsx json py rb go rs java kt kts swift c h cc cpp hpp cs php sh zsh bash fish ps1 sql yaml yml toml ini conf cfg xml css scss less lua pl r dart vue svelte gradle mk cmake");
put("csv", "csv tsv");
put("html", "html htm");
put("pdf", "pdf");
put("subtitle", "srt vtt ass ssa sub");

/// What kind a file is, by its name.
export function kindOf(name: string): DriveKind {
  const dot = name.lastIndexOf(".");
  const ext = dot <= 0 ? "" : name.slice(dot + 1).toLowerCase();
  if (ext === "" && /^(readme|license|licence|changelog|makefile|dockerfile)$/i.test(name)) return "text";
  return EXT[ext] ?? "other";
}

/// A file's time: 14:05 today, 9/27 this year, 2024/9/27 before.
export function driveTime(ms: number, c: Clock): string {
  const [year, month, day] = local(ms, c.offsetMin);
  if (localDay(ms, c.offsetMin) === localDay(c.now, c.offsetMin)) return clock(ms, c.offsetMin);
  return year === local(c.now, c.offsetMin)[0] ? `${month}/${day}` : `${year}/${month}/${day}`;
}

/// The topic's value as it goes out: entries with their kind and words, the count in a line.
export function shown(raw: J, c: Clock): J {
  if (!isObject(raw)) return raw;
  const lang = current();
  const entries = (Array.isArray(raw.entries) ? raw.entries : []).filter(isObject).map((e: J) => {
    const dir = e.dir === true;
    const size = typeof e.size === "number" ? e.size : 0;
    const mtime = typeof e.mtime === "number" ? e.mtime : 0;
    return { ...e, kind: dir ? "folder" : kindOf(String(get(e, "name") ?? "")), sizeText: dir ? "" : bytes(size), timeText: mtime > 0 ? driveTime(mtime, c) : "" };
  });
  const folders = entries.filter((e: J) => e.dir).length;
  const files = entries.length - folders;
  const parts = [folders > 0 ? tr(lang, "core-logic.drive.folders", { n: folders }) : null, files > 0 ? tr(lang, "core-logic.drive.files", { n: files }) : null].filter((p) => p !== null);
  return { ...raw, entries, folders, files, countText: parts.length > 0 ? parts.join(" · ") : tr(lang, "core-logic.drive.empty") };
}
