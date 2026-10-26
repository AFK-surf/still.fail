// The cards over the rail's places as the pointer rests on them (the `railCard` view; 2026-10-26 用户：「好几个 tab 都可以
// hover 出卡片，比如 chat，stations，profiles，usage，hover 都可以显示有意义的信息」「显示一些有用的统计信息」, then 「stations 和
// profiles tab 的 hover 卡片去掉吧，分享放到 usage 的 hover 卡片上」): 对话's and 用量's, what each is about at a glance,
// figures first. Each card is a line saying how it stands, a few figures (each its value over what it is of, one that
// wants a look coloured), lines of what it is made of (the models that spent most), the last 7 days as bars where it
// has them, and 分享卡片 where there is something to share.
import { t } from "../i18n.ts";
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

/// The 用量 place's, of the usage view of the last 7 days: what they cost (its line), today's of it, the input tokens;
/// each day's cost a bar (today's said); the models that cost most, each with its cost and share; 分享卡片 (`share`).
/// Nothing spent: its line says so, alone, nothing to share.
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
    share: true,
  };
}
