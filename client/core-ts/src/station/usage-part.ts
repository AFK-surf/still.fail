// A station's usage as held (GET /usage over the page's 60 days, with its history), brought up to date by reading again
// only the days a change touched: the station says when the earliest call it recorded was made (its `usage` event's
// `from`), and those days alone are read (GET /usage from that day, without the history). Read whole at every change
// while a page showed it, it was some 200 KB a minute while agents worked, and 2 to 23 s of the station's time a read on
// a station (2026-11-02), every other read of its devices' waiting behind it.
import { get, isObject } from "../util.ts";

type J = Record<string, unknown>;

const DAY_MS = 86_400_000;
export const USAGE_WEEKS = 52;

/// The day (YYYY-MM-DD, as the station names them) `at` (ms) is in, `offset` minutes east of UTC, and when it began.
export function dayOf(at: number, offset: number): { day: string; from: number } {
  const local = Math.trunc(at) + offset * 60_000;
  const start = local - (((local % DAY_MS) + DAY_MS) % DAY_MS);
  return { day: new Date(start).toISOString().slice(0, 10), from: start - offset * 60_000 };
}

/// The chart starts on Sunday, 51 weeks before this one, and ends at the next local midnight.
export function usageHistoryRange(now: number, offset: number): { from: number; to: number } {
  const today = dayOf(now, offset).from;
  const weekday = new Date(today + offset * 60_000).getUTCDay();
  return { from: today - (weekday + (USAGE_WEEKS - 1) * 7) * DAY_MS, to: today + DAY_MS };
}

/// Whether what is held is a whole read of the usage from `from` (the page's 60 days as they are now, in this time zone:
/// another day or zone reads another `from`), with its history: what a part can be put into.
export function holdsWhole(held: unknown, from: number): held is J {
  return isObject(held) && Number(get(held, "from")) === from && Array.isArray(get(held, "rows"))
    && get(held, "historyPending") !== true && (isObject(get(held, "history")) || get(held, "historyUnavailable") === true);
}

const arr = (v: unknown): J[] => (Array.isArray(v) ? (v.filter(isObject) as J[]) : []);
const n = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/// An update from a different statistics generation cannot be spliced into what was held from the old one.
export function sameDetailCoverage(held: unknown, part: unknown): boolean {
  return (get(held, "detailSince") ?? null) === (get(part, "detailSince") ?? null);
}

/// What is held, with the days from `day` on (the part's, read from `since`, ms) as `part` has them: its rows and the
/// tasks run here from then on in place of those held, the threads, people and prices it names added, the profiles as
/// it says them; and the history's days from then on changed as the rows changed (the tokens read and written, the
/// cache's too, and the calls). The rest of the history (cards, chats by place, those archived, tasks run here) stays
/// as last read whole.
export function withPart(held: J, part: unknown, day: string, since: number): J {
  if (!isObject(part)) return held;
  const rows = [...arr(get(held, "rows")).filter((r) => String(get(r, "day")) < day), ...arr(get(part, "rows"))];
  // The history's days from `day` on, each what it held less what the rows held of it, plus what the part's rows say:
  // the calls the rows do not cover (a day's before the station's detail began) stay counted. By day alone, however
  // the station split its days (by model before; not at all since).
  const change = new Map<string, { tokens: number; calls: number }>();
  const accumulate = (records: J[], sign: number) => { for (const r of records) {
    const d = String(get(r, "day"));
    if (d < day) continue;
    const at = change.get(d) ?? { tokens: 0, calls: 0 };
    at.tokens += sign * (n(get(r, "input")) + n(get(r, "cacheRead")) + n(get(r, "cacheWrite")) + n(get(r, "output")));
    at.calls += sign * n(get(r, "calls"));
    change.set(d, at);
  } };
  accumulate(arr(get(held, "rows")), -1);
  accumulate(arr(get(part, "rows")), 1);
  const full = get(held, "history");
  const history = isObject(full) ? full : get(held, "partialHistory");
  const byDay = new Map<string, { day: string; runtime: string; model: null; tokens: number; calls: number }>();
  const kept: J[] = [];
  for (const d of arr(get(history, "days"))) {
    const at = String(get(d, "day"));
    if (at < day) { kept.push(d); continue; }
    const sum = byDay.get(at) ?? { day: at, runtime: "", model: null, tokens: 0, calls: 0 };
    sum.tokens += n(get(d, "tokens"));
    sum.calls += n(get(d, "calls"));
    byDay.set(at, sum);
  }
  for (const [d, c] of change) {
    const sum = byDay.get(d) ?? { day: d, runtime: "", model: null, tokens: 0, calls: 0 };
    sum.tokens += c.tokens;
    sum.calls += c.calls;
    byDay.set(d, sum);
  }
  let updatedDays: J[] = [...kept, ...[...byDay.values()].filter((d) => d.tokens !== 0 || d.calls !== 0)];
  updatedDays.sort((a, b) => {
    const first = String(get(a, "day")), second = String(get(b, "day"));
    return first < second ? -1 : first > second ? 1 : 0;
  });
  const beforeDay = get(history, "beforeDay");
  const previousTotal = get(history, "tokens");
  let total: number | undefined;
  if (typeof beforeDay === "string" && typeof previousTotal === "number" && Number.isFinite(previousTotal)) {
    const tokensOf = (records: J[]) => records.filter((r) => String(get(r, "day")) >= day && String(get(r, "day")) < beforeDay)
      .reduce((sum, r) => sum + n(get(r, "input")) + n(get(r, "cacheRead")) + n(get(r, "cacheWrite")) + n(get(r, "output")), 0);
    total = previousTotal - tokensOf(arr(get(held, "rows"))) + tokensOf(arr(get(part, "rows")));
    updatedDays = updatedDays.filter((d) => String(get(d, "day")) < beforeDay);
  }
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
    ...(isObject(history) ? { [isObject(full) ? "history" : "partialHistory"]: { ...history, ...(total !== undefined ? { tokens: total } : {}), days: updatedDays } } : {}),
  };
}
