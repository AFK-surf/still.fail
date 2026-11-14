// What goes out of a topic is what goes out again when it is put out a second time: a value the core sends (output.ts:
// decorated by present.ts, put through its shape) held again unmarked inside another value and so decorated again
// (views.ts `asShaped`'s parts, as the store shares a value with the one before: #5326, a reset's end said as the page
// opened and gone a few seconds on, the user's 「重置时间显示一下又消失」 2026-11-11, Android 0.1.8285) says what it
// said. Each way the app asks a topic (`ASKED`) on the workspace of real size (real-size.ts), its value as the store
// holds it put out once, and what went out put out again as if it were the store's: the two the same, or the first
// path where they differ named. Known differences in `TWICE` (by the name `ASKED` gives it, the difference), which only
// falls (the user, 2026-11-11: 三条都加). DECORATE_TWICE_PRINT=1 prints each and fails nothing.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { Output } from "../src/output.ts";
import type { Clock } from "../src/present.ts";
import { ASKED, LONG, held, topicOf } from "./real-size-asked.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// Those whose value put out again differs now, by the name `ASKED` gives them: the first path that differs and how,
/// whole (a difference that changes, on the same path, is a fault too: #5326's reset said its end and then lost it,
/// where the reset's text already differed).
const TWICE: Record<string, string> = {
  "station": "overview.profiles[0].quota.resets[1].text: \"3 天后、9 天后到期 · 到达它能恢复的上限后才能用\", then \"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用\"",
  "chat": "agents[0].jobs[0].meta[1].text: \" · 5 小时\", then \" · 0 秒\"",
  "chat compact": "agents[0].hasJobs: true, then false",
  "messagePeek": "(whole): {\"author\":\"\",\"text\":\"结论 列表掉帧的根因是每一帧都在重新测量行高：measure_row 在滚动时被调用了 1,800 次/秒。 做了什么, then null",
  "job": "detail: \"运行中 · 20 小时 · 20 条通知\", then \"运行中 · 0 秒 · 20 条通知\"",
  "chat six pages": "agents[0].jobs[0].meta[1].text: \" · 5 小时\", then \" · 0 秒\"",
  "chat compact six pages": "agents[0].hasJobs: true, then false",
};

/// The first path where `a` and `b` differ, and how; null where they are the same.
function differs(a: J, b: J, at = ""): string | null {
  if (Object.is(a, b)) return null;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return `${at || "(whole)"}: ${a.length} items, then ${b.length}`;
    for (let i = 0; i < a.length; i++) {
      const d = differs(a[i], b[i], `${at}[${i}]`);
      if (d !== null) return d;
    }
    return null;
  }
  if (a !== null && b !== null && typeof a === "object" && typeof b === "object" && !Array.isArray(a) && !Array.isArray(b)) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = differs(a[k], b[k], at === "" ? k : `${at}.${k}`);
      if (d !== null) return d;
    }
    return null;
  }
  const said = (v: unknown) => (v === undefined ? "(none)" : JSON.stringify(v).slice(0, 80));
  return `${at || "(whole)"}: ${said(a)}, then ${said(b)}`;
}

test("what each topic the app asks sends is the same put out again on a workspace of real size", async () => {
  const faults: string[] = [];
  const seen = new Map<string, string | null>();
  for (const long of [false, true]) {
    const { t } = await held(long);
    try {
      const now = t.host.nowMs();
      const c: Clock = { now, offsetMin: t.host.utcOffsetMin(now) };
      for (const name of Object.keys(ASKED)) {
        if (LONG.has(name) !== long) continue;
        const topic = topicOf(name);
        const kept = t.store.value(topic);
        if (kept === undefined || !("ok" in kept)) {
          faults.push(`${name}: the store holds no value of it`);
          continue;
        }
        const once = new Output().shape(topic, kept.ok, c, true);
        if (!("ok" in once)) {
          faults.push(`${name}: put out once, its shape's error ${once.error}`);
          continue;
        }
        // (what went out, as a value of the store's holds it inside another: a copy, none of it marked as gone out)
        const twice = new Output().shape(topic, JSON.parse(JSON.stringify(once.ok)), c, true);
        seen.set(name, "ok" in twice ? differs(once.ok, twice.ok) : `(whole): put out again, its shape's error ${twice.error}`);
      }
    } finally {
      t.store.runner.shutdown();
    }
  }
  for (const [name, d] of seen) {
    const known = TWICE[name];
    if (d === null && known !== undefined) faults.push(`${name}: the same put out again now: bring it out of TWICE`);
    else if (d !== null && known === undefined) faults.push(`${name}: put out again, ${d}`);
    else if (d !== null && known !== undefined && d !== known) faults.push(`${name}: put out again, ${d} (TWICE says ${known})`);
  }
  for (const name of Object.keys(TWICE)) if (!seen.has(name)) faults.push(`${name}: in TWICE but not asked`);
  if (process.env.DECORATE_TWICE_PRINT === "1" || faults.length > 0) {
    console.log(["Put out again:", ...[...seen].map(([n, d]) => `    ${JSON.stringify(n)}: ${d === null ? "the same" : JSON.stringify(d)},`)].join("\n"));
  }
  if (process.env.DECORATE_TWICE_PRINT === "1") return;
  assert.deepEqual(faults, []);
});
