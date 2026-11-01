// A folder of a station's drive as the clients show it (the `drive` topic; docs/drive.md): each entry with what kind it
// is (which mark it has) and what a press on it does, its size and time in words, and the folder's count in a line.
import { bytes, clock, local, localDay } from "./format.ts";
import { current, tr, type Lang } from "./i18n.ts";
import type { Clock } from "./present.ts";
import { get, isObject } from "./util.ts";
import { kindOf, opensOf, type DriveKind } from "./drive-kind.ts";

export { kindOf, opensOf, type DriveKind, type DriveOpener } from "./drive-kind.ts";

type J = any;

/// What is wrong with a name a file or folder is given (empty, a slash, `.` or `..`), in words; null when nothing is.
export function nameProblem(name: string): string | null {
  const n = name.trim();
  if (n === "") return tr(current(), "core-logic.drive.name.empty");
  if (n.includes("/") || n.includes("\\") || n === "." || n === "..") return tr(current(), "core-logic.drive.name.bad");
  return null;
}

/// A file's time: 14:05 today, 9/27 this year, 2024/9/27 before.
export function driveTime(ms: number, c: Clock): string {
  const [year, month, day] = local(ms, c.offsetMin);
  if (localDay(ms, c.offsetMin) === localDay(c.now, c.offsetMin)) return clock(ms, c.offsetMin);
  return year === local(c.now, c.offsetMin)[0] ? `${month}/${day}` : `${year}/${month}/${day}`;
}

/// A folder's visible entries in words; a folder with only hidden entries is not an empty folder.
export function driveCount(folders: number, files: number, hiddenOnly = false, lang: Lang = current()): string {
  const parts = [folders > 0 ? tr(lang, "core-logic.drive.folders", { n: folders }) : null, files > 0 ? tr(lang, "core-logic.drive.files", { n: files }) : null].filter((p) => p !== null);
  return parts.length > 0 ? parts.join(" · ") : tr(lang, hiddenOnly ? "core-logic.drive.noVisible" : "core-logic.drive.empty");
}

/// The topic's value as it goes out: entries with their kind and words, the count in a line.
export function shown(raw: J, c: Clock): J {
  if (!isObject(raw)) return raw;
  const entries = (Array.isArray(raw.entries) ? raw.entries : []).filter(isObject).map((e: J) => {
    const dir = e.dir === true;
    const size = typeof e.size === "number" ? e.size : 0;
    const mtime = typeof e.mtime === "number" ? e.mtime : 0;
    const kind: DriveKind = dir ? "folder" : kindOf(String(get(e, "name") ?? ""));
    return { ...e, kind, opens: opensOf(kind), sizeText: dir ? "" : bytes(size), timeText: mtime > 0 ? driveTime(mtime, c) : "" };
  });
  const folders = entries.filter((e: J) => e.dir).length;
  const files = entries.length - folders;
  return { ...raw, entries, folders, files, countText: driveCount(folders, files) };
}
