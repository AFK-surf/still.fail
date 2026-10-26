// The cards over the rail's places as the pointer rests on them (the `railCard` view; 2026-10-26 用户：「好几个 tab 都可以
// hover 出卡片，比如 chat，stations，profiles，usage，hover 都可以显示有意义的信息」「显示一些有用的统计信息」, then of the
// stations' 「现在看着好像没啥东西」): what each place is about at a glance, figures first. Each card is a line saying how
// it stands, a few figures (each its value over what it is of, one that wants a look coloured), lines of what it is
// made of (each station, each kind of subscription, the models that spent most), the last 7 days as bars where it has
// them, and a line more where one says what the figures do not.
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import { isWatch } from "../jobs.ts";
import * as present from "../present.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { localDay } from "./usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);
const num = (v: unknown): number => (typeof v === "number" ? v : 0);

/// How a figure or a line stands out: red (gone wrong, used up), amber (wants a look soon); none: as it should be.
type Tone = "red" | "amber";
const toned = (tone: Tone | null) => (tone === null ? {} : { tone });

/// A figure: its value, what it is of.
const stat = (value: string | number, label: string, tone: Tone | null = null) => ({ value: String(value), label, ...toned(tone) });

/// The 对话 place's: how many chats are at work (its line), how many wait for the viewer, went wrong, have something
/// unread (the viewer's marks: views/marks.ts), and how many were archived today (`archived`, when each was, on a
/// clock `offset` minutes east of UTC; `now`).
export function chatsCard(rows: J[], mark: J, archived: number[], now: number, offset: number): J {
  const running = rows.filter((r) => present.rowState(arr(get(r, "agents"))) === "run").length;
  const wait = num(get(mark, "wait"));
  const alert = num(get(mark, "alert"));
  const today = localDay(now, offset);
  const done = archived.filter((at) => localDay(at, offset) === today).length;
  return {
    head: running > 0 ? t("core-logic.rail.chats.head", { n: running }) : t("core-logic.rail.chats.none"),
    stats: [
      stat(wait, t("core-logic.rail.chats.wait"), wait > 0 ? "amber" : null),
      stat(alert, t("core-logic.rail.chats.alert"), alert > 0 ? "red" : null),
      stat(num(get(mark, "unread")), t("core-logic.rail.chats.unread")),
      stat(done, t("core-logic.rail.chats.archived")),
    ],
    rows: [],
  };
}

/// A station as the Station place's card reads it: the chats view's (its name, what it is doing, how it is), its
/// machine as its host says (present.host: its chip, how full its CPU and memory are), its jobs.
export type RailStation = { station: J; host: J; jobs: J[] };

/// The Station place's: how many agents are at work (the glyph's line), how many stations are up of all, how many
/// tasks are at work on them; each station a line (what it is doing, red where it cannot be reached; its
/// chip, CPU and memory under it, coloured as full as they are). 分享卡片 while any agent is at work (`share`).
export function stationsCard(glyph: J, stations: RailStation[]): J {
  const up = stations.filter((s) => get(s.station, "state") === "online").length;
  const agents = num(get(glyph, "running"));
  // the tasks at work on them (a watch is not one; one waiting in a station's queue not yet)
  const tasks = stations
    .flatMap((s) => s.jobs)
    .filter((j) => get(j, "state") === "running" && get(j, "queued") !== true && !isWatch(j) && get(j, "port") == null).length;
  return {
    head: str(get(glyph, "now")) ?? str(get(glyph, "label")) ?? "",
    stats: [
      stat(`${up}/${stations.length}`, t("core-logic.rail.stations.online"), up < stations.length ? "amber" : null),
      stat(tasks, t("core-logic.rail.stations.tasks")),
    ],
    rows: stations.map((s) => {
      const up = get(s.station, "state") === "online";
      const meters = up ? arr(get(s.host, "meters")).slice(0, 2) : [];
      const model = up ? str(get(s.host, "identity"))?.split(" · ")[0] ?? null : null;
      const sub = [model, ...meters.map((m) => `${str(get(m, "short")) ?? ""} ${num(get(m, "percent"))}%`)].filter((x) => x !== null && x !== "");
      const worst = meters.some((m) => get(m, "level") === "red") ? "red" : meters.some((m) => get(m, "level") === "amber") ? "amber" : null;
      return {
        name: str(get(s.station, "name")) ?? "",
        value: str(get(s.station, "doing")) ?? "",
        ...(get(s.station, "state") === "error" ? { tone: "red" } : {}),
        ...(sub.length > 0 ? { sub: sub.join(" · "), ...(worst !== null ? { subTone: worst } : {}) } : {}),
      };
    }),
    share: agents > 0,
  };
}

/// The Profile place's: of the subscriptions whose quota is read (the profiles view's items), how many have room, how
/// many are nearly through a window of theirs (amber or red, present.leftLevel), how many used one up; each kind of
/// subscription a line (用 6 个 Claude 订阅账号消耗了 489% 的周额度, as the card shared says it: fleet.ts quotaOf); the one
/// that wants a look and refills soonest, when (`now`).
export function profilesCard(items: J[], quota: J[], now: number): J {
  let room = 0;
  let near = 0;
  let out = 0;
  let soonest: { name: string; at: number } | null = null;
  for (const item of items) {
    if (get(item, "group") === "key") continue;
    const p = get(item, "profile");
    const q = get(p, "quota");
    if (get(q, "state") !== "ok") continue;
    const windows = arr(get(q, "windows")).filter((w) => typeof w.usedPercent === "number");
    if (windows.length === 0) continue;
    const used = Math.max(...windows.map((w) => w.usedPercent as number));
    if (used >= 100) out++;
    else if (present.leftLevel(used)[1] !== "ok") near++;
    else room++;
    if (used >= 70) {
      const at = windows.filter((w) => (w.usedPercent as number) >= 70 && typeof w.resetsAt === "number").map((w) => w.resetsAt as number);
      const name = str(get(p, "name")) ?? str(get(p, "id")) ?? "";
      for (const a of at) if (a > now && (soonest === null || a < soonest.at)) soonest = { name, at: a };
    }
  }
  const all = room + near + out;
  return {
    head: out > 0 ? t("core-logic.rail.profiles.out_head", { n: out }) : t("core-logic.rail.profiles.head", { n: all }),
    stats: [
      stat(room, t("core-logic.rail.profiles.room")),
      stat(near, t("core-logic.rail.profiles.near"), near > 0 ? "amber" : null),
      stat(out, t("core-logic.rail.profiles.out"), out > 0 ? "red" : null),
    ],
    rows: quota.map((k) => ({ name: `${str(k.lead) ?? ""} ${str(k.usedText) ?? ""} ${str(k.of) ?? ""}`, value: "" })),
    ...(soonest !== null ? { note: t("core-logic.rail.profiles.soonest", { name: soonest.name, when: format.refillsIn(soonest.at, now) }) } : {}),
  };
}

/// The 用量 place's, of the usage view of the last 7 days: what they cost (its line), today's of it, the input tokens;
/// each day's cost a bar (today's said); the models that cost most, each with its cost and share. Nothing spent: its
/// line says so, alone.
export function usageCard(usage: J): J {
  if (get(usage, "empty") === true) return { head: t("core-logic.rail.usage.none"), stats: [], rows: [] };
  const tiles = arr(get(usage, "tiles"));
  const daily = arr(get(usage, "daily"));
  const today = daily.find((d) => d.today === true) ?? null;
  const most = Math.max(...daily.map((d) => num(d.cost)), 0);
  const models = arr(arr(get(usage, "lists")).find((l) => get(l, "key") === "models")?.items).slice(0, 3);
  const value = (x: J) => str(get(x, "value")) ?? "";
  return {
    head: t("core-logic.rail.usage.head", { cost: value(tiles[0]) }),
    stats: [
      stat(str(get(today, "costText")) ?? "", t("core-logic.rail.usage.today")),
      stat(value(tiles[2]), str(get(tiles[2], "label")) ?? ""),
    ],
    rows: models.map((m) => ({ name: str(get(m, "title")) ?? "", value: [str(get(m, "costText")), str(get(m, "shareText"))].filter((x) => x !== null).join(" · ") })),
    days: daily.map((d) => ({ label: str(d.label) ?? "", share: most > 0 ? num(d.cost) / most : 0, today: d.today === true })),
  };
}
