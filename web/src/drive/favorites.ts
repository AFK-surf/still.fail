// Folders a person keeps at hand on the files' page (its sidebar's 个人收藏), of any station of the workspace, as Finder's
// favourites: theirs alone, kept on this device among the prefs (`driveFavorites`, by workspace), not the station's
// pinned folders (which every member sees: 团队共享).
import { useMemo } from "react";
import { setPrefs, usePrefs } from "../prefs.ts";
import type { Pane } from "./tabs.ts";
import { absoluteOf } from "./useDrive.ts";

export interface Favorite extends Pane { name: string }

/** At most this many. */
const MOST = 40;

function read(raw: string | undefined): Favorite[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw) as unknown;
    if (!Array.isArray(v)) return [];
    const parsed = v.filter((f): f is Favorite => !!f && typeof f === "object" && ["station", "root", "path", "name"].every((k) => typeof (f as Record<string, unknown>)[k] === "string"));
    return parsed.filter((f, i) => parsed.findIndex((other) => sameFolder(f, other)) === i);
  } catch {
    return [];
  }
}

/** The absolute folder named by a root and a path; Windows separators differ from a backslash in a Unix name. */
function folderPath(p: Pane): string {
  const abs = absoluteOf(p.root, p.path);
  const separated = p.root.includes("\\") && !p.root.startsWith("/") ? abs.replaceAll("\\", "/") : abs;
  return separated === "/" ? separated : separated.replace(/\/+$/, "");
}

/** A shared root and the same folder reached from its parent are one place, on that station. */
export function sameFolder(a: Pane, b: Pane): boolean {
  return a.station === b.station && folderPath(a) === folderPath(b);
}

/** The workspace's favourites, and how to change them. */
export function useFavorites(workspace: string): { list: Favorite[]; has: (p: Pane) => boolean; add: (f: Favorite) => void; remove: (p: Pane) => void } {
  const raw = usePrefs((p) => p.driveFavorites[workspace]);
  const list = useMemo(() => read(raw), [raw]);
  const keep = (next: Favorite[]) => setPrefs({ driveFavorites: { [workspace]: JSON.stringify(next.slice(0, MOST)) } });
  return {
    list,
    has: (p) => list.some((f) => sameFolder(f, p)),
    add: (f) => { if (!list.some((x) => sameFolder(x, f))) keep([...list, f]); },
    remove: (p) => keep(list.filter((f) => !sameFolder(f, p))),
  };
}
