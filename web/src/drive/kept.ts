// What the files keep as they are left, as a local file browser does, for this page's life (not stored): how far each
// folder was scrolled (by where it is shown and how), the folder last open in a workspace's files' page (the rail's 文件
// comes back to it) and in its chats' 文件 tab (the same over each chat, as the tab is kept while chats change beside
// it). The folders a tree had open, a column's width dragged and what was last opened in each folder (chosen when it is
// shown again) are the core's (`drive.browse`, client/core-ts/src/views/browse.ts): `keepOpened` tells it.
import { useEffect, useLayoutEffect, useRef, type RefObject } from "react";
import { core } from "../core/react.ts";
import type { At } from "./model.ts";

/** Where a folder is shown: the files' page, or a chat's 文件 tab. */
export type Owner = "page" | "tab";

const keyOf = (owner: Owner, at: At, ...more: string[]) => [owner, at.station, at.root, at.path, ...more].join("\n");

const scrolls = new Map<string, number>();
const lastFolder = new Map<string, string>();
const tabs = new Map<string, unknown>();

/**
 * The element given the ref (or the one `scroller` finds from it: the page it is in) scrolled as far as when the folder
 * at `at`, shown `how`, was last left, once its entries are drawn (`ready`); one never shown from its top. Kept as it
 * scrolls, not while another folder is still being read into it (the browser pulls it back up then, which is not where
 * this one was left).
 */
export function useKeptScroll<T extends HTMLElement>(owner: Owner, at: At, how: string, ready: boolean, scroller?: (own: T) => HTMLElement | null): RefObject<T | null> {
  const own = useRef<T>(null);
  const key = keyOf(owner, at, how);
  // The folder in it now, and whether it has been put back where it was: a scroll comes after the folder changed
  // (the browser's own, as it pulls the next one up), so it counts for the one in it then.
  const now = useRef<{ key: string; shown: boolean }>({ key, shown: false });
  useLayoutEffect(() => {
    now.current = { key, shown: false };
    const el = own.current && (scroller ? scroller(own.current) : own.current);
    if (!el || !ready) return;
    el.scrollTop = scrolls.get(key) ?? 0;
    now.current.shown = true;
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `scroller` may be a new function each render; what it finds is not.
  }, [key, ready]);
  useEffect(() => {
    const el = own.current && (scroller ? scroller(own.current) : own.current);
    if (!el) return;
    const keep = () => { if (now.current.shown) scrolls.set(now.current.key, el.scrollTop); };
    el.addEventListener("scroll", keep, { passive: true });
    return () => el.removeEventListener("scroll", keep);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return own;
}

/** What was opened in the folder at `at` (a folder gone into, a file), by its name: chosen as it is shown again. */
export function keepOpened(owner: Owner, at: At, name: string): void {
  void core().call("drive.browse", { act: "opened", owner, station: at.station, root: at.root, path: at.path, name }).catch(() => undefined);
}

/** The files' page last open in workspace `scope` (its path and query). */
export function lastFilesPage(scope: string): string | undefined {
  return lastFolder.get(scope);
}
export function keepFilesPage(scope: string, page: string): void {
  lastFolder.set(scope, page);
}

/** Where the chats' 文件 tab was in workspace `scope`. */
export function keptTab<T>(scope: string): T | undefined {
  return tabs.get(scope) as T | undefined;
}
export function keepTab<T>(scope: string, place: T): void {
  tabs.set(scope, place);
}
