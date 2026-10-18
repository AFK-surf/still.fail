// The search (docs/search.md): what a few words find in a workspace, from wherever it is, as ⌘K and the phones' search
// list it. What the device holds is looked through here (the chats as the sidebar has them, the messages it keeps, the
// stations); what each station holds it says itself (its `stationSearch`: its chats archived or not, every message, the
// execution histories, its services and tasks, skills and memory, profiles), each as it answers, the rest shown
// meanwhile. The messages found here and there are one list, each once.
import { t } from "../i18n.ts";
import { waitNote } from "../looks.ts";
import * as present from "../present.ts";
import * as refs from "../refs.ts";
import type { Topic } from "../protocol.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// The kinds found, in the order they are listed.
export const KINDS = ["chat", "message", "file", "history", "job", "skill", "memory", "profile", "station"] as const;
/// How many of each kind the list shows with all of them; one kind alone (`kind`) shows this many.
export const SHOWN = 5;
export const ONE_KIND = 50;
/// The chats listed with nothing typed, and those whose title or line has the words with all kinds.
export const RECENT = 30;
export const CHATS_SHOWN = 8;

/// What the search reads of the views.
export type SearchSource = {
  value(topic: Topic): Value | undefined;
  ok(topic: Topic): J;
  stations(scope: string): { address: string; name: string; emoji: string | null; icon: string | null; online: boolean }[] | undefined;
  /// The messages the device holds that have the words, in the chats listed (newest first, at most `wanted`).
  foundMessages(chats: J, view: Topic): J[];
  me(scope: string): J;
  clock(): present.Clock;
};

/// What each station is asked for a search (`kind`: that kind alone, more of it).
export function stationTopic(station: string, view: Topic): Topic {
  const q = String(view.query ?? "").trim();
  const kind = typeof view.kind === "string" ? view.kind : undefined;
  return { topic: "stationSearch", station, q, ...(kind ? { kind } : {}), limit: kind ? ONE_KIND : SHOWN + 1 };
}

/// A chat found archived: marked so, its second line saying so where a list's says where it stands.
const archived = () => ({ archived: true, stateText: t("core-views.search.archived") });

const titled = (title: string, words: string[]) => words.length > 0 && title.toLowerCase().includes(words[0]!);

/// A chat a station found that the device's list does not have (archived, or not read yet): drawn as a row of it.
function chatRow(hit: J, s: { address: string; name: string }, chatTitle: string): J {
  const id = str(hit.chat) ?? "";
  return {
    id, session: id, thread: num(hit.thread), title: chatTitle || t("core-views.new_chat"), agents: [], unread: false, mine: false,
    lastActiveAt: num(hit.at) ?? 0, station: s.address, stationName: s.name, ...(hit.archived === true ? archived() : {}),
  };
}

export function searchView(src: SearchSource, chats: J, view: Topic): Value {
  const scope = view.scope as string;
  const query = String(view.query ?? "");
  const words = refs.terms(query);
  const kind = typeof view.kind === "string" ? view.kind : null;
  const wants = (k: string) => kind === null || kind === k;
  const limit = typeof view.limit === "number" && view.limit > 0 ? view.limit : kind ? ONE_KIND : SHOWN;
  const clock = src.clock();
  if (words.length === 0) {
    const recent = refs.search(chats, "", undefined, undefined, RECENT);
    return { ok: { items: recent.items, words: [], messages: [], groups: [], wait: waitNote([]) } };
  }
  const stations = src.stations(scope) ?? [];
  const several = stations.length > 1;
  const local = refs.search(chats, query, undefined, undefined, undefined);
  // The device's chats by station and thread, to draw what a station found as the sidebar draws it.
  const rows = new Map<string, J>();
  for (const item of arr(get(chats, "days")).flatMap((d) => arr(get(d, "items")))) if (typeof item.thread === "number") rows.set(`${item.station}\u0001${item.thread}`, item);
  const items: J[] = wants("chat") ? [...arr(local.items)] : [];
  const seenChats = new Set(items.map((i) => `${i.station}\u0001${i.id}`));
  const messages: J[] = wants("message") ? src.foundMessages(chats, { ...view, messages: limit }) : [];
  const seenMessages = new Set(messages.map((m) => `${m.station}\u0001${m.thread}\u0001${m.seq}`));
  const found = new Map<string, J[]>();
  const more = new Set<string>();
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const older: string[] = [];
  let building = false;
  const members = arr(get(src.ok({ topic: "workspace", workspace: scope }), "members"));
  const me = src.me(scope);
  for (const s of stations) {
    if (!s.online) continue;
    const answer = src.value(stationTopic(s.address, view));
    if (answer === undefined) {
      waiting.push(s.name);
      continue;
    }
    if ("err" in answer) {
      if (answer.err.status === 404) older.push(s.name);
      else failing.push({ station: s.address, name: s.name, message: answer.err.message });
      continue;
    }
    if (get(answer.ok, "building") === true) building = true;
    const mark = { station: s.address, stationName: s.name, ...(several && s.emoji ? { stationEmoji: s.emoji } : {}), ...(several && s.icon ? { stationIcon: s.icon } : {}) };
    for (const group of arr(get(answer.ok, "groups"))) {
      const k = str(get(group, "kind"));
      if (k === null || !wants(k)) continue;
      const hits = arr(get(group, "hits"));
      if (get(group, "more") === true || hits.length > (kind ? ONE_KIND : SHOWN)) more.add(k);
      for (const hit of hits) {
        const thread = num(hit.thread);
        const row = thread === null ? undefined : rows.get(`${s.address}\u0001${thread}`);
        if (k === "chat") {
          const id = str(row?.id) ?? str(hit.chat);
          if (id === null) continue;
          if (seenChats.has(`${s.address}\u0001${id}`)) {
            // The device's row of it, archived meanwhile (its station says so before the list does): said archived.
            const at = hit.archived === true ? items.findIndex((i) => i.station === s.address && i.id === id) : -1;
            if (at >= 0 && items[at].archived !== true) items[at] = { ...items[at], ...archived() };
            continue;
          }
          seenChats.add(`${s.address}\u0001${id}`);
          items.push(row ?? chatRow(hit, s, str(hit.title) ?? ""));
          continue;
        }
        if (k === "message") {
          const seq = num(hit.seq);
          if (thread === null || seq === null || seenMessages.has(`${s.address}\u0001${thread}\u0001${seq}`)) continue;
          seenMessages.add(`${s.address}\u0001${thread}\u0001${seq}`);
          const chat = row ?? chatRow(hit, s, str(hit.chatTitle) ?? "");
          const said = { last: { authorKind: hit.authorKind, author: hit.author, agentIdentity: hit.agentIdentity }, agents: chat.agents };
          const by = present.lastBy(said, me, [], members);
          const message: J = { station: s.address, thread, seq, by: str(get(by, "name")) ?? "", ...refs.excerpt(String(hit.text ?? ""), words) };
          if (num(hit.at) !== null) message.createdAt = hit.at;
          messages.push({ chat, ...(present.times(message, clock) as J) });
          continue;
        }
        const item: J = {
          kind: k, key: `${s.address}\u0001${String(hit.key)}`, ...mark,
          title: itemTitle(k, hit), ...refs.excerpt(String(hit.text ?? ""), words),
        };
        for (const f of ["chat", "chatTitle", "session", "skill", "profile", "job", "path", "tool"] as const) if (typeof hit[f] === "string" && hit[f] !== "") item[f] = hit[f];
        for (const f of ["thread", "seq", "index", "port"] as const) if (num(hit[f]) !== null) item[f] = hit[f];
        if (hit.archived === true) item.archived = true;
        if (num(hit.at) !== null) item.createdAt = hit.at;
        const list = found.get(k) ?? [];
        list.push(present.times(item, clock));
        found.set(k, list);
      }
    }
  }
  // The stations whose name has the words: the device knows them.
  if (wants("station")) {
    const named = stations.filter((s) => words.every((w) => s.name.toLowerCase().includes(w)));
    if (named.length > 0) {
      found.set("station", named.map((s) => ({
        kind: "station", key: s.address, station: s.address, stationName: s.name, ...(s.emoji ? { stationEmoji: s.emoji } : {}), ...(s.icon ? { stationIcon: s.icon } : {}),
        title: s.name, text: s.online ? "" : t("core-views.search.offline"), marks: [],
      })));
    }
  }
  // Those whose title has the first word first, then the newest; one list across stations.
  const order = (a: J, b: J) => Number(titled(String(b.title ?? ""), words)) - Number(titled(String(a.title ?? ""), words)) || (num(b.createdAt) ?? 0) - (num(a.createdAt) ?? 0);
  messages.sort((a, b) => (num(b.createdAt) ?? 0) - (num(a.createdAt) ?? 0));
  const groups: J[] = [];
  for (const k of KINDS) {
    const list = (found.get(k) ?? []).sort(order);
    if (list.length === 0) continue;
    groups.push({ kind: k, title: t(`core-views.search.kind.${k}`), items: list.slice(0, limit), more: more.has(k) || list.length > limit });
  }
  const notes: string[] = [];
  if (older.length > 0) notes.push(t("core-views.search.older", { names: older.join("、") }));
  if (building) notes.push(t("core-views.search.building"));
  const offline = stations.filter((s) => !s.online).map((s) => s.name);
  if (offline.length > 0) notes.push(t("core-views.search.offlineStations", { names: offline.join("、") }));
  const shownItems = items.slice(0, kind === "chat" ? limit : kind ? 0 : CHATS_SHOWN);
  return {
    ok: {
      items: shownItems,
      chatsMore: items.length > shownItems.length,
      words,
      messages: messages.slice(0, limit),
      messagesMore: messages.length > limit || more.has("message"),
      groups,
      wait: waitNote(waiting, failing, shownItems.length === 0 && messages.length === 0 && groups.length === 0),
      ...(notes.length > 0 ? { note: notes.join(" · ") } : {}),
    },
  };
}

/// What a found thing is called in the list.
function itemTitle(kind: string, hit: J): string {
  const title = str(hit.title) ?? "";
  if (kind === "history") return str(hit.chatTitle) || t("core-views.new_chat");
  if (kind === "memory") return t("core-views.search.memory");
  return title;
}
