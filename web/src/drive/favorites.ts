// Folders a person keeps at hand on the files' page (its sidebar's 个人收藏), of any station of the workspace, as Finder's
// favourites: theirs alone, kept on this device among the prefs (`driveFavorites`, by workspace), not the station's
// pinned folders (which every member sees: 团队共享).
import { useMemo } from "react";
import { setPrefs, usePrefs } from "../prefs.ts";
import type { Pane } from "./tabs.ts";

export interface Favorite extends Pane { name: string }

/** At most this many. */
const MOST = 40;

function read(raw: string | undefined): Favorite[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw) as unknown;
    return Array.isArray(v) ? v.filter((f): f is Favorite => !!f && typeof f === "object" && ["station", "root", "path", "name"].every((k) => typeof (f as Record<string, unknown>)[k] === "string")) : [];
  } catch {
    return [];
  }
}

const same = (a: Pane, b: Pane) => a.station === b.station && a.root === b.root && a.path === b.path;

/** The workspace's favourites, and how to change them. */
export function useFavorites(workspace: string): { list: Favorite[]; has: (p: Pane) => boolean; add: (f: Favorite) => void; remove: (p: Pane) => void } {
  const raw = usePrefs((p) => p.driveFavorites[workspace]);
  const list = useMemo(() => read(raw), [raw]);
  const keep = (next: Favorite[]) => setPrefs({ driveFavorites: { [workspace]: JSON.stringify(next.slice(0, MOST)) } });
  return {
    list,
    has: (p) => list.some((f) => same(f, p)),
    add: (f) => { if (!list.some((x) => same(x, f))) keep([...list, f]); },
    remove: (p) => keep(list.filter((f) => !same(f, p))),
  };
}
