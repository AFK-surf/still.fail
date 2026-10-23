// A chat's side panel (web/src/pages/ChatPage.tsx, the mbui app's wide_panel.mbt): the tabs open beside it and the one in
// front, kept on this device for each chat (prefs `chatTabs`, by `<station>:<session>` as its page names it; `new:<workspace>`
// for a workspace's new chat). What a client draws is the chat view's `tabs`: those kept that the chat has, and the one
// in front; it changes them with `chat.tabs.open/close/front/clear`, which keep the result. Self-contained: the web's
// demo shows and changes its chats' tabs with it, typechecked as the web is.

type Obj = Record<string, unknown>;
const isObject = (v: unknown): v is Obj => v !== null && typeof v === "object" && !Array.isArray(v);
const get = (v: unknown, k: string): unknown => (isObject(v) ? v[k] : undefined);

/// The tabs that are not an agent's history: its agents' services and jobs (任务), the stations' files (文件), the
/// letters its agents and other chats wrote each other (往来).
export const JOBS = "jobs";
export const FILES = "files";
export const LETTERS = "letters";

export type Tabs = { open: string[]; shown?: string; auto?: true };
/// What is kept for a chat: its tabs, and the one in front when there is one.
export type Kept = { tabs: string[]; active?: string };

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);

/// A visualization's tab (`file:["<session>","<path>","<name>"]`, web/src/Preview.tsx fileService).
function isFile(key: string): boolean {
  if (!key.startsWith("file:")) return false;
  try {
    const v = JSON.parse(key.slice("file:".length));
    return Array.isArray(v) && typeof v[0] === "string" && typeof v[1] === "string" && typeof v[2] === "string";
  } catch {
    return false;
  }
}

/// The agents' session keys and their jobs' ids, as the chat view has them.
function chatHas(agents: readonly unknown[]): { histories: Set<string>; jobs: Set<string> } {
  const histories = new Set<string>();
  const jobs = new Set<string>();
  for (const a of agents) {
    const key = get(get(a, "session"), "key");
    if (typeof key === "string") histories.add(key);
    const js = get(a, "jobs");
    for (const j of Array.isArray(js) ? js : []) {
      const id = get(j, "id");
      if (typeof id === "string") jobs.add(id);
    }
  }
  return { histories, jobs };
}

/// The tabs a chat shows: those kept (`kept`, prefs `chatTabs`) that it has — an agent's history, a service of one of
/// its agents' (`service:<job>`), 任务, 文件, 往来, a visualization — all of them while its agents are not known yet (the
/// panel holds its place); the one in front: the one kept so, else the first. None kept: none, but where its agent has
/// no chat yet (`noChat`, by its `session`) its history, opened by itself (`auto`: a client where the panel would lie
/// over the chat shows none).
export function tabsOf(kept: unknown, agents: readonly unknown[], noChat: boolean, session: string | null): Tabs {
  const chosen = isObject(kept) && Array.isArray(kept.tabs) ? strings(kept.tabs) : null;
  const auto = chosen === null && noChat && session !== null;
  const tabs = chosen ?? (auto && session !== null ? [session] : []);
  const has = chatHas(agents);
  const known = (key: string) => key === JOBS || key === FILES || key === LETTERS || isFile(key) || (key.startsWith("service:") && has.jobs.has(key.slice("service:".length))) || has.histories.has(key);
  const open = agents.length ? tabs.filter(known) : tabs;
  const active = isObject(kept) && typeof kept.active === "string" ? kept.active : null;
  const shown = active !== null && open.includes(active) ? active : open[0];
  return { open, ...(shown !== undefined ? { shown } : {}), ...(auto ? { auto: true as const } : {}) };
}

export type Change = { action: "open" | "close" | "front" | "clear"; tab: string | null; auto: boolean };

/// What is kept after a change, from what the chat shows (`tabsOf`; `auto` false: a client that shows none opened by
/// itself, which it goes from); null when nothing changes. Opened: in front, an agent's history after the histories
/// open (before the other tabs), any other last. Closed: the one in front, if it was, the last left. In front: as said.
/// Cleared (the panel closed): none, the one in front kept as it was.
export function changed(kept: unknown, agents: readonly unknown[], noChat: boolean, session: string | null, change: Change): Kept | null {
  const now = tabsOf(kept, agents, noChat, session);
  const open = now.auto && !change.auto ? [] : now.open;
  const shown = now.auto && !change.auto ? null : now.shown ?? null;
  const active = isObject(kept) && typeof kept.active === "string" ? kept.active : null;
  const { histories } = chatHas(agents);
  const isAgent = (key: string) => histories.has(key);
  const tab = change.tab ?? "";
  const keep = (tabs: string[], front: string | null): Kept => (front ? { tabs, active: front } : { tabs });
  switch (change.action) {
    case "open": {
      if (isAgent(tab) && !open.includes(tab)) {
        let at = 0;
        open.forEach((k, i) => { if (isAgent(k)) at = i + 1; });
        return keep([...open.slice(0, at), tab, ...open.slice(at)], tab);
      }
      return keep(open.includes(tab) ? open : [...open, tab], tab);
    }
    case "close": {
      if (!open.includes(tab)) return null;
      const next = open.filter((k) => k !== tab);
      return keep(next, shown === tab ? next.at(-1) ?? null : active);
    }
    case "front":
      return keep(open, tab);
    case "clear":
      return keep([], active);
  }
}
