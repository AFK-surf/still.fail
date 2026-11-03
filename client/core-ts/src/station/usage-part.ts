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
  return isObject(held) && Number(get(held, "from")) === from && Array.isArray(get(held, "rows"))
    && (isObject(get(held, "history")) || get(held, "historyUnavailable") === true);
}

const arr = (v: unknown): J[] => (Array.isArray(v) ? (v.filter(isObject) as J[]) : []);
const n = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/// An update from a different statistics generation cannot be spliced into what was held from the old one.
export function sameDetailCoverage(held: unknown, part: unknown): boolean {
  return (get(held, "detailSince") ?? null) === (get(part, "detailSince") ?? null);
}

/// What is held, with the days from `day` on (the part's, read from `since`, ms) as `part` has them: its rows and the
/// tasks run here from then on in place of those held, the threads, people and prices it names added, the profiles as
/// it says them; and the history's days from then on added up again from the rows, as the station adds them up (the
/// tokens read and written, the cache's too, and the calls, by day, runtime and model). The rest of the history (cards,
/// chats by place, those archived, tasks run here) stays as last read whole.
export function withPart(held: J, part: unknown, day: string, since: number): J {
  if (!isObject(part)) return held;
  const rows = [...arr(get(held, "rows")).filter((r) => String(get(r, "day")) < day), ...arr(get(part, "rows"))];
  type Day = { day: string; runtime: string; model: string | null; tokens: number; calls: number };
  const days = new Map<string, Day>();
  const accumulate = (target: Map<string, Day>, records: J[], sign: number) => { for (const r of records) {
    const d = String(get(r, "day"));
    if (d < day) continue;
    const runtime = String(get(r, "runtime"));
    const model = typeof get(r, "model") === "string" ? (get(r, "model") as string) : null;
    const key = `${d}\n${runtime}\n${model ?? ""}`;
    const at = target.get(key) ?? { day: d, runtime, model, tokens: 0, calls: 0 };
    at.tokens += sign * (n(get(r, "input")) + n(get(r, "cacheRead")) + n(get(r, "cacheWrite")) + n(get(r, "output")));
    at.calls += sign * n(get(r, "calls"));
    target.set(key, at);
  } };
  accumulate(days, rows, 1);
  const full = get(held, "history");
  const history = isObject(full) ? full : get(held, "partialHistory");
  const historyDays = arr(get(history, "days"));
  let updatedDays: J[];
  if (typeof get(held, "detailSince") === "number") {
    // A complete day can include older calls which the new detail index intentionally does not contain. Apply only
    // the change in the new detail, rather than replacing that complete day with the partial detail's total.
    const totals = new Map<string, Day>();
    for (const d of historyDays) {
      const item = { day: String(get(d, "day")), runtime: String(get(d, "runtime")), model: typeof get(d, "model") === "string" ? get(d, "model") as string : null,
        tokens: n(get(d, "tokens")), calls: n(get(d, "calls")) };
      totals.set(`${item.day}\n${item.runtime}\n${item.model ?? ""}`, item);
    }
    accumulate(totals, arr(get(held, "rows")), -1);
    accumulate(totals, arr(get(part, "rows")), 1);
    updatedDays = [...totals.values()].filter((d) => d.calls !== 0 || d.tokens !== 0);
  } else {
    updatedDays = [...historyDays.filter((d) => String(get(d, "day")) < day), ...days.values()];
  }
  updatedDays.sort((a, b) => {
    const first = String(get(a, "day")), second = String(get(b, "day"));
    return first < second ? -1 : first > second ? 1 : 0;
  });
  const priced = new Map<string, J>();
  for (const p of [...arr(get(get(held, "prices"), "rows")), ...arr(get(get(part, "prices"), "rows"))]) priced.set(String(get(p, "model")), p);
  const { remoteRuns: _remoteRuns, history: _history, partialHistory: _partialHistory, ...rest } = held;
  const detailSince = get(part, "detailSince") ?? get(held, "detailSince");
  const remoteRuns = Array.isArray(get(held, "remoteRuns")) && Array.isArray(get(part, "remoteRuns"))
    ? [...arr(get(held, "remoteRuns")).filter((r) => n(get(r, "at")) < since), ...arr(get(part, "remoteRuns"))] : undefined;
  return {
    ...rest,
    since: get(part, "since") ?? get(held, "since") ?? null,
    ...(typeof detailSince === "number" ? { detailSince } : {}),
    reading: get(part, "reading") ?? get(held, "reading"),
    prices: { ...(isObject(get(held, "prices")) ? (get(held, "prices") as J) : {}), ...(isObject(get(part, "prices")) ? (get(part, "prices") as J) : {}), rows: [...priced.values()] },
    rows,
    threads: { ...(get(held, "threads") as J | undefined), ...(get(part, "threads") as J | undefined) },
    people: { ...(get(held, "people") as J | undefined), ...(get(part, "people") as J | undefined) },
    profiles: get(part, "profiles") ?? get(held, "profiles"),
    ...(remoteRuns !== undefined ? { remoteRuns } : {}),
    ...(isObject(history) ? { [isObject(full) ? "history" : "partialHistory"]: { ...history, days: updatedDays } } : {}),
  };
}
