// The archive (views/archive.rs): the archived chats of a scope's stations online in one list, newest first by the
// day they were archived; only those whose title or last line has `q` in it or in which their station finds it (every
// message, docs/search.md), and only the newest `limit` of them (it can be very long: the page asks for more as it is scrolled to its end). One on its way out of the archive from here is gone from it at once (local.ts).
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
  const items: J[] = [];
  const errors: J[] = [];
  let loading = false;
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const needle = q.trim().toLowerCase();
  const words = needle.split(/\s+/).filter((w) => w !== "");
  const has = (text: string) => words.every((w) => text.toLowerCase().includes(w));
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
    const v = views.value({ topic: "archivedRows", station: s.address });
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
    for (const chat of arr(v.ok)) {
      if (!isObject(get(chat, "archived")) || local.restoring(s.address, chat)) continue;
      const mark = chat.archived;
      const atRaw = get(mark, "at") ?? get(chat, "lastActiveAt");
      const at = typeof atRaw === "number" ? atRaw : 0;
      const text = (x: J) => (typeof x === "string" ? x : "");
      const id = text(get(chat, "id"));
      const found = hits.get(id) ?? (get(chat, "thread") == null ? undefined : hits.get(get(chat, "thread")));
      const title = text(get(chat, "title"));
      const lastLine = text(get(get(chat, "last"), "text"));
      if (needle && !has(title) && !has(lastLine) && found === undefined) continue;
      items.push({
        station: s.address,
        id,
        session: text(get(chat, "session")),
        thread: get(chat, "thread") ?? null,
        title,
        // Found by a message of it: that message, where the words are, not its last line that has none of them.
        last: found && !has(lastLine) ? refs.excerpt(found, words).text : lastLine,
        at,
        clock: format.clock(at, host.utcOffsetMin(at)),
        how: get(mark, "by") === "auto" ? t("core-views.archive.auto") : t("core-views.archive.manual"),
        deletable: get(mark, "alone") !== true,
        place,
        ...(named && s.emoji ? { stationEmoji: s.emoji } : {}),
        ...(named && s.icon ? { stationIcon: s.icon } : {}),
      });
    }
  }
  items.sort((a, b) => b.at - a.at);
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
  return { ok: { days: days.map(([label, list]) => ({ label, items: list })), errors, note, total: items.length, more: shown.length < items.length, wait: waitNote(waiting, failing, items.length === 0) } };
}

/// The chat list's day headings, with the year before this one's.
export function dayLabel(at: number, now: number, offset: number): string {
  const label = format.dayLabel(at, now, offset);
  const year = format.local(at, offset)[0];
  const dated = format.localDay(now, offset) - format.localDay(at, offset) >= 7;
  return dated && year !== format.local(now, offset)[0] ? t("core-views.archive.day_with_year", { year, day: label }) : label;
}
