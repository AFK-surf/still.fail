// The files' page's tabs, as Finder's: each a folder of a station of the workspace, or two side by side (one of them in
// front: what the keys, ⌘C and the page's address are about); one tab shown at a time. What they hold and what is done
// to them; ./tabs.ts keeps them on this device. The page's address is always the folder in front, in the tab shown
// (`/w/<ws>/s/<station>/files?root=&path=`): a link, the sidebar or going back in history moves that one, and the tabs
// follow it (`arrive`).

/** One side of a tab: a folder of a station (its address), by one of its roots and a path under it. */
export interface Pane { station: string; root: string; path: string }
export interface FilesTab { id: string; panes: Pane[]; front: number }
export interface FilesTabs { tabs: FilesTab[]; current: string }

/** At most this many tabs (the oldest let go past it). */
export const MOST_TABS = 12;

const same = (a: Pane, b: Pane) => a.station === b.station && a.root === b.root && a.path === b.path;
const isPane = (v: unknown): v is Pane => !!v && typeof v === "object" && ["station", "root", "path"].every((k) => typeof (v as Record<string, unknown>)[k] === "string");

/** What is kept, read: what does not hold together is let go. */
export function readTabs(raw: string | undefined): FilesTabs | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as FilesTabs;
    const tabs = (Array.isArray(v?.tabs) ? v.tabs : []).filter((t) => typeof t?.id === "string" && Array.isArray(t.panes) && t.panes.length >= 1 && t.panes.length <= 2 && t.panes.every(isPane))
      .map((t) => ({ id: t.id, panes: t.panes, front: t.front === 1 && t.panes.length === 2 ? 1 : 0 }));
    if (tabs.length === 0) return null;
    return { tabs, current: tabs.some((t) => t.id === v.current) ? v.current : tabs[0]!.id };
  } catch {
    return null;
  }
}

/** A tab's id: new each time, short. */
const newId = () => Math.random().toString(36).slice(2, 10);

/** The pane in front of the tab shown. */
export function frontOf(s: FilesTabs): Pane {
  const tab = s.tabs.find((t) => t.id === s.current) ?? s.tabs[0]!;
  return tab.panes[tab.front] ?? tab.panes[0]!;
}

// ── what is done to them (each answers the tabs after it) ──

/** The address moved (a link, the sidebar, history): the pane in front shows it; with no tabs yet, the first. */
export function arrive(s: FilesTabs | null, p: Pane): FilesTabs {
  if (!s) {
    const first = { id: newId(), panes: [p], front: 0 };
    return { tabs: [first], current: first.id };
  }
  const tabs = s.tabs.map((t) => (t.id !== s.current || same(t.panes[t.front]!, p) ? t : { ...t, panes: t.panes.map((x, i) => (i === t.front ? p : x)) }));
  return { ...s, tabs };
}

/** A new tab showing `p`, after the one shown, in front. */
export function opened(s: FilesTabs, p: Pane): FilesTabs {
  const tab = { id: newId(), panes: [p], front: 0 };
  const at = s.tabs.findIndex((t) => t.id === s.current);
  const tabs = [...s.tabs.slice(0, at + 1), tab, ...s.tabs.slice(at + 1)];
  return { tabs: tabs.length > MOST_TABS ? tabs.filter((t) => t.id !== s.tabs[0]!.id || t.id === tab.id) : tabs, current: tab.id };
}

/** A tab closed (the last one is not: it stays, as Finder keeps a window); the one beside it shown. */
export function closed(s: FilesTabs, id: string): FilesTabs {
  if (s.tabs.length <= 1) return s;
  const at = s.tabs.findIndex((t) => t.id === id);
  const tabs = s.tabs.filter((t) => t.id !== id);
  return { tabs, current: s.current === id ? tabs[Math.min(at, tabs.length - 1)]!.id : s.current };
}

export const shown = (s: FilesTabs, id: string): FilesTabs => (s.tabs.some((t) => t.id === id) ? { ...s, current: id } : s);

/** The tab shown split in two (the other side opening on `other`, else where the front is), or one again (the side in
 * front kept). */
export function split(s: FilesTabs, other?: Pane): FilesTabs {
  return {
    ...s,
    tabs: s.tabs.map((t) => {
      if (t.id !== s.current) return t;
      if (t.panes.length === 2) return { ...t, panes: [t.panes[t.front]!], front: 0 };
      return { ...t, panes: [t.panes[0]!, other ?? t.panes[0]!], front: 1 };
    }),
  };
}

/** The side `front` of the tab shown put in front. */
export function fronted(s: FilesTabs, front: number): FilesTabs {
  return { ...s, tabs: s.tabs.map((t) => (t.id === s.current && t.panes[front] ? { ...t, front } : t)) };
}

/** A tab's title: its front's folder (both sides', split). */
export function tabTitle(t: FilesTab, name: (p: Pane) => string): string {
  return t.panes.map(name).join(" | ");
}

/** `p` on the other side of the tab shown (split first if it is not), put in front. */
export function besides(s: FilesTabs, p: Pane): FilesTabs {
  return {
    ...s,
    tabs: s.tabs.map((t) => {
      if (t.id !== s.current) return t;
      if (t.panes.length === 1) return { ...t, panes: [t.panes[0]!, p], front: 1 };
      const other = t.front === 0 ? 1 : 0;
      return { ...t, panes: t.panes.map((x, i) => (i === other ? p : x)), front: other };
    }),
  };
}
