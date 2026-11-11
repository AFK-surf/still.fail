// A station's backups as its 设置 shows them (copies.ts): one row, and on a new station a backup of a station no
// longer there to restore; and a lost station's links opening the station that took its place (asks.ts `linkNow`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { linkNow, linkTarget } from "../src/asks.ts";
import { conform } from "../src/conform.ts";
import { copiesShown } from "../src/copies.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();
const c = { now: 10 * 60_000, offsetMin: 0 };
const A = "a".repeat(64);
const B = "b".repeat(64);
const C = "c".repeat(64);

const keeper = (station: string, name: string, o: { to?: number; at?: number | null; error?: string | null; reason?: string | null }) =>
  ({ station, name, to: o.to ?? 7, at: o.at === undefined ? 8 * 60_000 : o.at, error: o.error ?? null, reason: o.reason ?? null });

test("its backups in one row: the stations up to date and since when; one not reached or behind said briefly", () => {
  const both = copiesShown({ to: 7, chats: 12, keepers: [keeper(A, "Cedar", {}), keeper(B, "Aspen", { at: 9 * 60_000 })], empty: false, manage: true, formerly: [] }, c);
  assert.equal(both.line, "已备份到 Cedar 和 Aspen · 1 分钟前");
  assert.equal(both.level, "ok");
  assert.deepEqual(both.offers, []);
  assert.ok("ok" in conform("StationCopies", both), JSON.stringify(conform("StationCopies", both)));
  const one = copiesShown({ to: 7, chats: 12, keepers: [keeper(A, "Cedar", {}), keeper(B, "Aspen", { error: "station unreachable", reason: "offline" })], empty: false, formerly: [] }, c);
  assert.equal(one.line, "已备份到 Cedar · 2 分钟前 · Aspen 连不上");
  assert.equal(one.level, "amber");
  const behind = copiesShown({ to: 7, chats: 12, keepers: [keeper(A, "Cedar", { to: 3 }), keeper(B, "Aspen", { error: "x", reason: "old" })], empty: false, formerly: [] }, c);
  assert.equal(behind.line, "还没备份好 · Cedar 还没跟上 · Aspen 版本太旧");
});

test("the only station of its workspace says another one backs it up; backups stopped say why", () => {
  const alone = copiesShown({ to: 1, chats: 2, keepers: [], empty: false, formerly: [] }, c);
  assert.equal(alone.line, "再加一台 station 就会自动备份");
  const stopped = copiesShown({ to: 1, chats: 2, keepers: [keeper(A, "Cedar", {})], stopped: { error: "SQLITE_FULL", tries: 3, reason: "full" }, empty: false, formerly: [] }, c);
  assert.equal(stopped.line, "备份停了：磁盘满了，会自己再试");
  assert.equal(stopped.level, "red");
});

test("a new station: a backup of a station no longer there in the row's place, how its restore goes in the same row", () => {
  const offered = { looking: false, at: 1, copies: [{ station: A, name: "Old Mac", gen: "1-abcdef01", made: 60_000, to: 9, chats: 128, from: [{ station: B, name: "Cedar" }] }] };
  const v = copiesShown({ to: 0, chats: 0, keepers: [], empty: true, manage: true, formerly: [], restorable: offered, restoring: null }, c);
  assert.equal(v.offers.length, 1);
  assert.equal(v.offers[0].line, "Old Mac 的 128 个聊天");
  assert.equal(v.offers[0].fromStation, B);
  assert.equal(v.canRestore, true);
  assert.ok("ok" in conform("StationCopies", v), JSON.stringify(conform("StationCopies", v)));
  const going = copiesShown({ to: 0, chats: 0, keepers: [], empty: true, manage: true, formerly: [], restorable: offered,
    restoring: { origin: A, name: "Old Mac", workspace: "w", gen: "1-abcdef01", from: B, done: 37, total: 412, error: null, restart: false } }, c);
  assert.equal(going.offers.length, 1, "one row, not one beside it");
  assert.equal(going.offers[0].line, "正在恢复：37 / 412 个文件");
  assert.equal(going.offers[0].busy, true);
  assert.equal(going.canRestore, false, "not while one is under way");
  // a station with chats, or a viewer who may not: nothing to restore, or no press
  assert.deepEqual(copiesShown({ to: 3, chats: 1, keepers: [], empty: false, formerly: [], restorable: offered }, c).offers, []);
  assert.equal(copiesShown({ to: 0, chats: 0, keepers: [], empty: true, manage: false, formerly: [], restorable: offered }, c).canRestore, false);
});

test("after the restart, what came of the restore in the row until a station is up to date with it; one that left files to place says so", () => {
  const restored = { origin: C, name: "Old Mac", from: A, at: 8 * 60_000, rows: { threads: 128, entries: 900 }, files: 12, missing: 0, error: null, reason: null, pending: false, left: 0 };
  const now = copiesShown({ to: 7, chats: 128, keepers: [keeper(A, "Cedar", { at: null })], restored, empty: false, formerly: [C] }, c);
  assert.equal(now.line, "已恢复 Old Mac 的 128 个聊天 · 2 分钟前");
  const later = copiesShown({ to: 7, chats: 128, keepers: [keeper(A, "Cedar", {})], restored, empty: false, formerly: [C] }, c);
  assert.equal(later.line, "已备份到 Cedar · 2 分钟前", "said no more once a station is up to date");
  const pending = copiesShown({ to: 7, chats: 128, keepers: [keeper(A, "Cedar", {})], empty: false, formerly: [C],
    restored: { ...restored, error: "ENOSPC", reason: "full", pending: true, left: 3 } }, c);
  assert.equal(pending.line, "已恢复 Old Mac 的聊天，还有 3 个附件下次启动接着放：磁盘满了");
  for (const v of [now, later, pending]) assert.doesNotMatch(JSON.stringify(v), /副本|取回|保管|丢失|文件夹/);
});

test("a link to a lost station's chat opens the station that took its place", () => {
  const target = linkTarget(`https://app.still.fail/o/ws1/${A}/chat%3Ax`, "https://app.still.fail");
  const now = (address: string) => (address === `ws1/${A}` ? `ws1/${B}` : address);
  assert.equal(linkNow(target, now).station, B);
  assert.equal(linkNow(target, now).session, "chat:x");
  assert.equal(linkNow(linkTarget("https://app.still.fail/invite#t", "https://app.still.fail"), now).opens, "invite");
});
