// The order a folder's entries are shown in and the names a change gives, as a local file browser has them: folders
// first, then by name (numbers as numbers), time, size or kind; hidden files (a name starting with `.`) left out unless
// asked for; a new folder named as Finder names one; a station's files dragged into a folder, each one rename.
import type { DriveEntry } from "../core/shapes.ts";

/** A folder (its station, its root, its path under that root). */
interface Folder { station: string; root: string; path: string }
/** A station's file dragged (as ./drag.ts has it): where it is, by its root and absolutely, and its name. */
interface Moving { station: string; root: string; abs: string; name: string }

export type SortBy = "name" | "time" | "size" | "kind";
/** How a folder's entries are shown: ordered by what, the other way (`down`), hidden ones too. */
export interface Arrangement { by: SortBy; down: boolean; hidden: boolean }

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
const extOf = (name: string) => { const dot = name.lastIndexOf("."); return dot > 0 ? name.slice(dot + 1).toLowerCase() : ""; };

/** A folder's entries as they are shown: hidden ones left out unless asked for, folders first, then by what was chosen
 * (the newest and the largest first unless turned the other way, names A to Z). */
export function arrange(entries: readonly DriveEntry[], a: Arrangement): DriveEntry[] {
  const shown = a.hidden ? [...entries] : entries.filter((e) => !e.name.startsWith("."));
  const byName = (x: DriveEntry, y: DriveEntry) => collator.compare(x.name, y.name);
  const by: (x: DriveEntry, y: DriveEntry) => number =
    a.by === "time" ? (x, y) => y.mtime - x.mtime || byName(x, y)
    : a.by === "size" ? (x, y) => y.size - x.size || byName(x, y)
    : a.by === "kind" ? (x, y) => collator.compare(x.kind, y.kind) || collator.compare(extOf(x.name), extOf(y.name)) || byName(x, y)
    : byName;
  return shown.sort((x, y) => (x.dir !== y.dir ? (x.dir ? -1 : 1) : a.down ? by(y, x) : by(x, y)));
}

/** A name not taken in `entries`: `base`, else `base 2`, `base 3`…, as Finder names a new folder. */
export function freeName(entries: readonly DriveEntry[], base: string): string {
  const taken = new Set(entries.map((e) => e.name.toLowerCase()));
  if (!taken.has(base.toLowerCase())) return base;
  for (let n = 2; ; n++) if (!taken.has(`${base} ${n}`.toLowerCase())) return `${base} ${n}`;
}

/**
 * The renames a drag of a station's files into the folder `into` makes: none for one dragged from another station, one
 * where it is already, or one into itself; each by a root both places are under (the one it was dragged from, or the
 * folder's), else, for a member who browses every folder, by the top of the disk.
 */
export function movesOf(items: readonly Moving[], into: Folder, anywhere: boolean): { root: string; from: string; to: string }[] {
  const dest = absoluteOf(into.root, into.path);
  const sep = sepOf(dest);
  const under = (path: string, top: string) => path === top || path.startsWith(top.endsWith(sep) ? top : top + sep);
  const out: { root: string; from: string; to: string }[] = [];
  for (const item of items) {
    if (item.station !== into.station) continue;
    const target = childOf(dest, item.name);
    if (target === item.abs || under(dest, item.abs)) continue;
    const root = [item.root, into.root].find((r) => under(item.abs, r) && under(target, r)) ?? (anywhere && sep === "/" ? "/" : null);
    if (root === null) continue;
    const rel = (abs: string) => (abs === root ? "" : abs.slice(root.length).replace(/^[/\\]+/, "").split(sep).join("/"));
    out.push({ root, from: rel(item.abs), to: rel(target) });
  }
  return out;
}

// As ./useDrive.ts has them, here without what that needs (this file is read by tests outside a page).
const sepOf = (path: string) => (path.includes("\\") && !path.includes("/") ? "\\" : "/");
const childOf = (folder: string, name: string) => (folder.endsWith(sepOf(folder)) ? `${folder}${name}` : `${folder}${sepOf(folder)}${name}`);
const absoluteOf = (root: string, path: string) => path.split("/").filter(Boolean).reduce((at, name) => childOf(at, name), root);
