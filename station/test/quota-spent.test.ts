// What a window of a profile's allowance used over the last 7 days (accounts/spent.ts), from how full it read along the
// way (store.ts quota_readings).
import assert from "node:assert/strict";
import { test } from "node:test";
import { type QuotaReading, spentSince } from "../src/accounts/spent.ts";
import { Store } from "../src/store/store.ts";

const H = 3600_000;
const D = 24 * H;
const WEEK = 7 * 24 * 60;
const at = (h: number, used: number, ends: number | null, minutes: number | null = WEEK): QuotaReading => ({ at: h * H, used, ends, minutes });

test("a week used over the span is what it grew by in it, all a week that began in it read, not how full it reads now", () => {
  const since = 10 * D;
  // read 60% when the span began, at 90% when its week ended (day 12), then 25% of the next: 30 + 25
  assert.equal(spentSince([at(5 * 24, 40, 12 * D), at(10 * 24, 60, 12 * D), at(11 * 24, 90, 12 * D), at(13 * 24, 25, 19 * D)], since), 55);
  // its reset moved by minutes between readings: the same week
  assert.equal(spentSince([at(9 * 24, 50, 12 * D), at(11 * 24, 70, 12 * D + 20 * 60_000)], since), 20);
  // reset by hand (its end where it was, how full it is lower): from naught
  assert.equal(spentSince([at(9 * 24, 80, 12 * D), at(11 * 24, 10, 12 * D)], since), 10);
  // first read in the span: a week begun in it counts all it reads, one begun before it is where counting starts
  assert.equal(spentSince([at(11 * 24, 30, 18 * D), at(12 * 24, 45, 18 * D)], since), 45);
  assert.equal(spentSince([at(11 * 24, 30, 15 * D), at(12 * 24, 45, 15 * D)], since), 15);
  // nothing read in the span: none used
  assert.equal(spentSince([at(9 * 24, 80, 12 * D)], since), 0);
});

test("a station keeps how full each window read where it changed, 8 days and the last before them, and reads them from the last before the span", () => {
  const store = Store.open(":memory:");
  const quota = (h: number, week: number, five: number) => ({
    state: "ok", detail: null, checkedAt: h * H,
    windows: [{ label: "5 小时", usedPercent: five, resetsAt: null, minutes: 300 }, { label: "每周", usedPercent: week, resetsAt: 30 * D, minutes: WEEK }],
  });
  store.setProfileQuota("p", quota(0, 10, 1));
  store.setProfileQuota("p", quota(1 * 24, 20, 1));
  store.setProfileQuota("p", quota(2 * 24, 20, 2));
  store.setProfileQuota("p", quota(12 * 24, 50, 2));
  // not ok: nothing read of it
  store.setProfileQuota("p", { state: "unavailable", windows: [], detail: "", checkedAt: 13 * 24 * H });
  store.setProfileQuota("q", quota(12 * 24, 99, 9));
  const week = store.quotaReadings("p", 5 * D).get("每周")!;
  // day 0's let go (more than 8 days before day 12, and not the last before them); day 2's unchanged: not kept
  assert.deepEqual(week.map((r) => [r.at / H, r.used]), [[24, 20], [12 * 24, 50]]);
  assert.equal(spentSince(week, 5 * D), 30);
  assert.deepEqual(store.quotaReadings("p", 5 * D).get("5 小时")!.map((r) => [r.at / H, r.used]), [[2 * 24, 2]]);
  store.close();
});
