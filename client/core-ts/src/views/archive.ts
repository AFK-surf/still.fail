// The archive (views/archive.rs): the archived chats of a scope's stations online in one list, newest first by the
// day they were archived. One on its way out of the archive from here is gone from it at once (local.ts).
import * as format from "../format.ts";
import type { Host } from "../host.ts";
import { t } from "../i18n.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import type { Local } from "./local.ts";
import type { Views } from "./views.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

export function archive(views: Views, local: Local, scope: string, host: Host): Value {
  const ws = views.value({ topic: "workspace", workspace: scope });
  if (ws === undefined) return { ok: { days: [], errors: [], loading: true, note: t("core-views.archive.reading_stations") } };
  if ("err" in ws) return ws;
  const online = (views.stations(scope) ?? []).filter((s) => s.online);
  const named = online.length > 1;
  const items: J[] = [];
  const errors: J[] = [];
  let loading = false;
  for (const s of online) {
    const place = named ? s.name : null;
    const v = views.value({ topic: "archivedRows", station: s.address });
    if (v === undefined) {
      loading = true;
      continue;
    }
    if ("err" in v) {
      errors.push({ station: s.address, text: place !== null ? t("core-views.named_error", { name: place, error: v.err.message }) : v.err.message });
      continue;
    }
    for (const chat of arr(v.ok)) {
      if (!isObject(get(chat, "archived")) || local.restoring(s.address, chat)) continue;
      const mark = chat.archived;
      const atRaw = get(mark, "at") ?? get(chat, "lastActiveAt");
      const at = typeof atRaw === "number" ? atRaw : 0;
      const text = (x: J) => (typeof x === "string" ? x : "");
      items.push({
        station: s.address,
        session: text(get(chat, "session")),
        thread: get(chat, "thread") ?? null,
        title: text(get(chat, "title")),
        last: text(get(get(chat, "last"), "text")),
        at,
        clock: format.clock(at, host.utcOffsetMin(at)),
        how: get(mark, "by") === "auto" ? t("core-views.archive.auto") : t("core-views.archive.manual"),
        deletable: get(mark, "alone") !== true,
        place,
      });
    }
  }
  items.sort((a, b) => b.at - a.at);
  const now = host.nowMs();
  const offset = host.utcOffsetMin(now);
  const days: [string, J[]][] = [];
  for (const item of items) {
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
          ? t("core-views.archive.empty")
          : null;
  return { ok: { days: days.map(([label, list]) => ({ label, items: list })), errors, loading, note } };
}

/// The chat list's day headings, with the year before this one's.
export function dayLabel(at: number, now: number, offset: number): string {
  const label = format.dayLabel(at, now, offset);
  const year = format.local(at, offset)[0];
  const dated = format.localDay(now, offset) - format.localDay(at, offset) >= 7;
  return dated && year !== format.local(now, offset)[0] ? t("core-views.archive.day_with_year", { year, day: label }) : label;
}
