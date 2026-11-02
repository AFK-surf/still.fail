// A station's usage as held (GET /usage over the page's 60 days, with its history), brought up to date by reading again
// only the days a change touched: the station says when the earliest call it recorded was made (its `usage` event's
// `from`), and those days alone are read (GET /usage from that day, without the history). Read whole at every change
// while a page showed it, it was some 200 KB a minute while agents worked, and 2 to 23 s of the station's time a read on
// ccvm (2026-11-02), every other read of its devices' waiting behind it.
import { get, isObject } from "../util.ts";

type J = Record<string, unknown>;

const DAY_MS = 86_400_000;

/// The day (YYYY-MM-DD, as the station names them) `at` (ms) is in, `offset` minutes east of UTC, and when it began.
export function dayOf(at: number, offset: number): { day: string; from: number } {
  const local = Math.trunc(at) + offset * 60_000;
  const start = local - (((local % DAY_MS) + DAY_MS) % DAY_MS);
  return { day: new Date(start).toISOString().slice(0, 10), from: start - offset * 60_000 };
}

/// Whether what is held is a whole read of the usage from `from` (the page's 60 days as they are now, in this time zone:
/// another day or zone reads another `from`), with its history: what a part can be put into.
export function holdsWhole(held: unknown, from: number): held is J {
  return isObject(held) && Number(get(held, "from")) === from && Array.isArray(get(held, "rows")) && isObject(get(held, "history"));
}

const arr = (v: unknown): J[] => (Array.isArray(v) ? (v.filter(isObject) as J[]) : []);
const n = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/// What is held, with the days from `day` on (the part's, read from `since`, ms) as `part` has them: its rows and the
/// tasks run here from then on in place of those held, the threads, people and prices it names added, the profiles as
/// it says them; and the history's days from then on added up again from the rows, as the station adds them up (the
/// tokens read and written, the cache's too, and the calls, by day, runtime and model). The rest of the history (cards,
/// chats by place, those archived, tasks run here) stays as last read whole.
export function withPart(held: J, part: unknown, day: string, since: number): J {
  if (!isObject(part)) return held;
  const rows = [...arr(get(held, "rows")).filter((r) => String(get(r, "day")) < day), ...arr(get(part, "rows"))];
  const days = new Map<string, { day: string; runtime: string; model: string | null; tokens: number; calls: number }>();
  for (const r of rows) {
    const d = String(get(r, "day"));
    if (d < day) continue;
    const runtime = String(get(r, "runtime"));
    const model = typeof get(r, "model") === "string" ? (get(r, "model") as string) : null;
    const key = `${d}\n${runtime}\n${model ?? ""}`;
    const at = days.get(key) ?? { day: d, runtime, model, tokens: 0, calls: 0 };
    at.tokens += n(get(r, "input")) + n(get(r, "cacheRead")) + n(get(r, "cacheWrite")) + n(get(r, "output"));
    at.calls += n(get(r, "calls"));
    days.set(key, at);
  }
  const history = get(held, "history") as J;
  const before = arr(get(history, "days")).filter((d) => String(get(d, "day")) < day);
  const priced = new Map<string, J>();
  for (const p of [...arr(get(get(held, "prices"), "rows")), ...arr(get(get(part, "prices"), "rows"))]) priced.set(String(get(p, "model")), p);
  return {
    ...held,
    since: get(part, "since") ?? get(held, "since") ?? null,
    reading: get(part, "reading") ?? get(held, "reading"),
    prices: { ...(isObject(get(held, "prices")) ? (get(held, "prices") as J) : {}), ...(isObject(get(part, "prices")) ? (get(part, "prices") as J) : {}), rows: [...priced.values()] },
    rows,
    threads: { ...(get(held, "threads") as J | undefined), ...(get(part, "threads") as J | undefined) },
    people: { ...(get(held, "people") as J | undefined), ...(get(part, "people") as J | undefined) },
    profiles: get(part, "profiles") ?? get(held, "profiles"),
    remoteRuns: [...arr(get(held, "remoteRuns")).filter((r) => n(get(r, "at")) < since), ...arr(get(part, "remoteRuns"))],
    history: { ...history, days: [...before, ...[...days.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0))] },
  };
}
