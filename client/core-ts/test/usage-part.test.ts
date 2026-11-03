// A station's usage held whole, brought up to date with the days a change touched read again (station/usage-part.ts):
// the same as reading it all again would have given.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dayOf, holdsWhole, withPart } from "../src/station/usage-part.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const DAY = 86_400_000;

const row = (day: string, session: string, model: string | null, calls: number, extra: J = {}): J => ({
  day, session, thread: 7, person: "a@x", profile: "cc", runtime: "claude", model, calls, input: 10 * calls, cacheRead: 90 * calls, cacheWrite: 5 * calls, output: calls, cost: null, ...extra,
});

/// What the station's history says of these rows' days (read/usage.ts usageHistory): tokens and calls by day, runtime
/// and model.
const daysOf = (rows: J[]): J[] => {
  const out = new Map<string, J>();
  for (const r of rows) {
    const key = `${r.day}\n${r.runtime}\n${r.model ?? ""}`;
    const d = out.get(key) ?? { day: r.day, runtime: r.runtime, model: r.model, tokens: 0, calls: 0 };
    d.tokens += r.input + r.cacheRead + r.cacheWrite + r.output;
    d.calls += r.calls;
    out.set(key, d);
  }
  return [...out.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
};

test("a day and when it began, in a time zone", () => {
  // 2026-11-03 01:30 in UTC+8 is 2026-11-02 17:30 UTC.
  const at = Date.UTC(2026, 10, 2, 17, 30);
  assert.deepEqual(dayOf(at, 480), { day: "2026-11-03", from: Date.UTC(2026, 10, 2, 16, 0) });
  assert.deepEqual(dayOf(at, 0), { day: "2026-11-02", from: Date.UTC(2026, 10, 2) });
  assert.deepEqual(dayOf(at, -300), { day: "2026-11-02", from: Date.UTC(2026, 10, 2, 5, 0) });
});

test("the days a change touched, read again, take the place of those held; the rest is as read whole", () => {
  const from = Date.UTC(2026, 8, 5, 16);
  const before = [row("2026-11-01", "s1", "m", 2), row("2026-11-02", "s1", "m", 1), row("2026-11-02", "s2", null, 4), row("2026-11-03", "s1", "m", 1)];
  const held: J = {
    from, to: 9223372036854775807, since: 1, reading: false,
    prices: { note: "按公开价", rows: [{ model: "m", input: 1, output: 2 }] },
    rows: before,
    threads: { "7": { title: "修登录" } },
    people: { "a@x": { id: "a@x" } },
    profiles: { cc: { name: "公司账号" } },
    remoteRuns: [{ at: Date.UTC(2026, 10, 1, 3), session: "remote:w:a" }, { at: Date.UTC(2026, 10, 2, 3), session: "remote:w:b" }],
    history: { days: [{ day: "2026-09-30", runtime: "claude", model: "m", tokens: 7, calls: 1 }, ...daysOf(before)], cards: 3, picked: 1, places: { ember: 2 }, archived: 1, remoteRuns: 2 },
  };
  assert.equal(holdsWhole(held, from), true);
  assert.equal(holdsWhole(held, from + DAY), false, "another day's window");
  assert.equal(holdsWhole({ ...held, history: undefined }, from), false, "a read without the history");
  // Calls recorded from 2026-11-02 on (UTC+8): that day and the next read again.
  const since = Date.UTC(2026, 10, 1, 16);
  const after = [row("2026-11-02", "s1", "m", 3), row("2026-11-02", "s2", null, 4), row("2026-11-03", "s1", "m", 2), row("2026-11-03", "s3", "n", 1, { thread: 8 })];
  const part: J = {
    from: since, to: 9223372036854775807, since: 1, reading: false,
    prices: { note: "按公开价", rows: [{ model: "m", input: 1, output: 2 }, { model: "n", input: 3, output: 4 }] },
    rows: after,
    threads: { "8": { title: "#ops" } },
    people: { "a@x": { id: "a@x" } },
    profiles: { cc: { name: "公司账号" } },
    remoteRuns: [{ at: Date.UTC(2026, 10, 2, 3), session: "remote:w:b" }, { at: Date.UTC(2026, 10, 2, 9), session: "remote:w:c" }],
  };
  const now: J = withPart(held, part, "2026-11-02", since);
  // As read whole: the rows of every day, those days' history added up from them, what the part names added.
  const whole = [row("2026-11-01", "s1", "m", 2), ...after];
  assert.deepEqual(now.rows, whole);
  assert.deepEqual(now.history, { ...held.history, days: [{ day: "2026-09-30", runtime: "claude", model: "m", tokens: 7, calls: 1 }, ...daysOf(whole)] });
  assert.deepEqual(now.threads, { "7": { title: "修登录" }, "8": { title: "#ops" } });
  assert.deepEqual(now.prices.rows.map((p: J) => p.model), ["m", "n"]);
  assert.deepEqual(now.remoteRuns.map((r: J) => r.session), ["remote:w:a", "remote:w:b", "remote:w:c"]);
  assert.equal(now.from, from, "still the whole window's");
  assert.equal(holdsWhole(now, from), true);
});

test("a full response without historical statistics still permits a partial refresh", () => {
  const from = Date.UTC(2026, 8, 5, 16), since = Date.UTC(2026, 10, 1, 16);
  const held: J = { from, rows: [row("2026-11-01", "s", "m", 1)], historyUnavailable: true, detailSince: from + DAY };
  assert.equal(holdsWhole(held, from), true);
  const part: J = { rows: [row("2026-11-02", "s", "m", 2)], detailSince: from + DAY };
  const updated: J = withPart(held, part, "2026-11-02", since);
  assert.deepEqual(updated.rows.map((r: J) => r.calls), [1, 2]);
  assert.equal(updated.historyUnavailable, true);
  assert.equal(updated.detailSince, from + DAY);
  assert.equal("history" in updated, false, "missing history is not made into an empty summary");
  assert.equal("remoteRuns" in updated, false, "missing remote tasks are not made into zero tasks");
});
