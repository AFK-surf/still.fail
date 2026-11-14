// The archive (views/archive.rs): the archived chats of a scope's stations online in one list, newest first by the
// day they were archived; only those whose title or last line has `q` in it or in which their station finds it (every
// message), and only the newest `limit` of them (it can be very long: the page asks for more as it is scrolled to its end). One on its way out of the archive from here is gone from it at once (local.ts).
import * as format from "../format.ts";
import type { Host } from "../host.ts";
import { t } from "../i18n.ts";
import { waitNote } from "../looks.ts";
import type { Topic } from "../protocol.ts";
import * as refs from "../refs.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import type { Local } from "./local.ts";
import type { Views } from "./views.ts";
import { CHAT_READS } from "../db/chat-reads.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// How many of each kind a station is asked to find in its archive.
const FOUND = 200;

/// What a station is asked for words looked for in its archive.
export const archiveSearch = (station: string, q: string): Topic => ({ topic: "stationSearch", station, q: q.trim(), kind: "chat,message", limit: FOUND, archived: true });

export function archive(views: Views, local: Local, scope: string, host: Host, q = "", limit = 0): Value {
  const ws = views.value({ topic: "workspace", workspace: scope });
  if (ws === undefined) return { ok: { days: [], errors: [], note: t("core-views.archive.reading_stations"), total: 0, more: false, wait: waitNote(null) } };
  if ("err" in ws) return ws;
  const online = (views.stations(scope) ?? []).filter((s) => s.online);
  const named = online.length > 1;
  const errors: J[] = [];
  let loading = false;
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const needle = q.trim().toLowerCase();
  const words = needle.split(/\s+/).filter((w) => w !== "");
  const has = (text: string) => words.every((w) => text.toLowerCase().includes(w));
  // What each station found, by chat and by thread (`hits`), and the stations whose archive is read (`read`).
  const hitsOf = new Map<string, Map<unknown, string>>();
  const read: string[] = [];
  for (const s of online) {
    const place = named ? s.name : null;
    // What the station finds in its archive, by chat and by thread: what a message said, "" for a chat found by its name.
    const hits = new Map<unknown, string>();
    if (needle) {
      const answer = views.value(archiveSearch(s.address, q));
      if (answer === undefined) {
        loading = true;
        if (!waiting.includes(s.name)) waiting.push(s.name);
      } else if ("err" in answer) {
        if (answer.err.status !== 404) failing.push({ station: s.address, name: s.name, message: answer.err.message });
      } else {
        for (const group of arr(get(answer.ok, "groups"))) {
          for (const hit of arr(get(group, "hits"))) {
            // A station from before finds in every chat, not only the archived.
            if (get(hit, "archived") !== true) continue;
            const said = get(group, "kind") === "message" ? String(get(hit, "text") ?? "") : "";
            for (const key of [get(hit, "chat"), get(hit, "thread")]) if (key != null && !hits.get(key)) hits.set(key, said);
          }
        }
      }
    }
    // The archive's pages still coming: what is not found yet may be in them. One that stopped short: said so.
    const link = views.value({ topic: "link", station: s.address });
    const state = link !== undefined && "ok" in link ? link.ok : null;
    if (needle && get(state, "archiveReading") === true) {
      loading = true;
      if (!waiting.includes(s.name)) waiting.push(s.name);
    }
    const stopped = get(state, "archiveFailed");
    if (typeof stopped === "string") errors.push({ station: s.address, text: place !== null ? t("core-views.named_error", { name: place, error: stopped }) : stopped });
    const v = views.listKnown(s.address, "archived");
    if (v === undefined) {
      loading = true;
      waiting.push(s.name);
      continue;
    }
    if ("err" in v) {
      failing.push({ station: s.address, name: s.name, message: v.err.message });
      errors.push({ station: s.address, text: place !== null ? t("core-views.named_error", { name: place, error: v.err.message }) : v.err.message });
      continue;
    }
    hitsOf.set(s.address, hits);
    read.push(s.address);
  }
  // The archived chats of the stations read, newest first, of their columns (db/chat-reads.ts `archived`: SQLite reading
  // what is shown of each of their JSON, the `limit` newest alone where nothing is looked for); those overlaid here read
  // apart by their keys and judged as their records say (local.ts restoring), and counted with the rest.
  const sorted: { item: J; place: number[] }[] = [];
  const data = views.data;
  const threads: string[] = [];
  const sessions: string[] = [];
  for (const a of read) {
    const o = local.overlaid(a);
    for (const t0 of o.threads) threads.push(`${a}\u0001${t0}`);
    for (const k of o.sessions) sessions.push(`${a}\u0001${k}`);
  }
  const stationOf = new Map(online.map((s) => [s.address, s]));
  const text = (x: J) => (typeof x === "string" ? x : "");
  const put = (station: string, id: string, at: number, session: string, thread: J, title: string, lastLine: string, by: J, alone: boolean, ord: number) => {
    const s = stationOf.get(station)!;
    const hits = hitsOf.get(station) ?? new Map<unknown, string>();
    const found = hits.get(id) ?? (thread == null ? undefined : hits.get(thread));
    if (needle && !has(title) && !has(lastLine) && found === undefined) return;
    sorted.push({
      place: [-at, read.indexOf(station), ord],
      item: {
        station,
        id,
        session,
        thread: thread ?? null,
        title,
        // Found by a message of it: that message, where the words are, not its last line that has none of them.
        last: found && !has(lastLine) ? refs.excerpt(found, words).text : lastLine,
        at,
        clock: format.clock(at, host.utcOffsetMin(at)),
        how: by === "auto" ? t("core-views.archive.auto") : t("core-views.archive.manual"),
        deletable: !alone,
        place: named ? s.name : null,
        ...(named && s.emoji ? { stationEmoji: s.emoji } : {}),
        ...(named && s.icon ? { stationIcon: s.icon } : {}),
      },
    });
  };
  let total = 0;
  if (read.length > 0) {
    const p = { stations: read, threads, sessions, limit: needle || limit <= 0 ? -1 : limit };
    for (const f of data.chatCounted(CHAT_READS.archived, p)) {
      const [station, , id, at, session, thread, title, lastLine, by, alone, ord] = f;
      put(String(station), String(id), Number(at), text(session), thread, text(title), text(lastLine), by, alone === 1, Number(ord));
    }
    if (!needle) for (const r of data.chatCounted(CHAT_READS.archivedCount, { ...p, from: Number.MAX_SAFE_INTEGER, offset: 0, day: 1 })) if (r[1] === null) total += Number(r[2]);
    if (threads.length > 0 || sessions.length > 0) {
      for (const f of data.chatFound(CHAT_READS.overlaid, { stations: read, archived: true, threads, sessions })) {
        const chat = f.record;
        if (!isObject(get(chat, "archived")) || local.restoring(f.station, chat)) continue;
        const mark = chat.archived;
        const atRaw = get(mark, "at") ?? get(chat, "lastActiveAt");
        const before = sorted.length;
        put(f.station, text(get(chat, "id")), typeof atRaw === "number" ? atRaw : 0, text(get(chat, "session")), get(chat, "thread"), text(get(chat, "title")), text(get(get(chat, "last"), "text")), get(mark, "by"), get(mark, "alone") === true, typeof f.cols[0] === "number" ? f.cols[0] : 0);
        if (!needle && sorted.length > before) total++;
      }
    }
  }
  sorted.sort((a, b) => {
    for (let i = 0; i < a.place.length; i++) if (a.place[i] !== b.place[i]) return a.place[i] - b.place[i];
    return a.item.id < b.item.id ? -1 : a.item.id > b.item.id ? 1 : 0;
  });
  const items = sorted.map((x) => x.item);
  if (needle) total = items.length;
  const shown = limit > 0 ? items.slice(0, limit) : items;
  const now = host.nowMs();
  const offset = host.utcOffsetMin(now);
  const days: [string, J[]][] = [];
  for (const item of shown) {
    const label = dayLabel(item.at, now, offset);
    const last = days[days.length - 1];
    if (last && last[0] === label) last[1].push(item);
    else days.push([label, [item]]);
  }
  const note =
    online.length === 0
      ? t("core-views.archive.none_online")
      : days.length === 0 && loading
        ? t("core-views.archive.reading")
        : days.length === 0 && errors.length === 0
          ? t(needle ? "core-views.archive.no_match" : "core-views.archive.empty")
          : null;
  return { ok: { days: days.map(([label, list]) => ({ label, items: list })), errors, note, total, more: shown.length < total, wait: waitNote(waiting, failing, total === 0) } };
}

/// The chat list's day headings, with the year before this one's.
export function dayLabel(at: number, now: number, offset: number): string {
  const label = format.dayLabel(at, now, offset);
  const year = format.local(at, offset)[0];
  const dated = format.localDay(now, offset) - format.localDay(at, offset) >= 7;
  return dated && year !== format.local(now, offset)[0] ? t("core-views.archive.day_with_year", { year, day: label }) : label;
}
