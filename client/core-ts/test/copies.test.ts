// A station's backups as its 设置 shows them (copies.ts): one row, and on a new station a backup of a station no
// longer there to restore; a station retired and one taking a retired one's chats in, as its page's 迁移 says them;
// and a lost station's links opening the station that took its place (asks.ts `linkNow`).
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

test("a station retired: its steps a row each, done, under way, failed or not yet, what may be done of it as its station says; may be retired only by one who manages it, while it has chats and none is recorded", () => {
  const base = { to: 7, chats: 12, keepers: [keeper(A, "Cedar", {})], empty: false, manage: true, formerly: [] };
  const free = copiesShown(base, c);
  assert.equal(free.canRetire, true, "one who manages it may retire it");
  assert.equal(free.retire, null);
  assert.deepEqual(free.taking, []);
  assert.equal(copiesShown({ ...base, manage: false }, c).canRetire, false, "not one who does not manage it");
  assert.equal(copiesShown({ ...base, chats: 0 }, c).canRetire, false, "not one with no chats");
  assert.equal(copiesShown({ ...base, empty: true, chats: 0 }, c).canRetire, false, "not a new station");
  const retiring = (step: string, o: Record<string, unknown> = {}, manage = true) =>
    copiesShown({ ...base, manage, retiring: { workspace: "w", to: B, toName: "Aspen", by: "p@x", at: 1, step, done: 1_500_000, total: 3_200_000_000, error: null, reason: null, cancellable: false, retriable: false, home: true, accountsLeft: [], ...o } }, c);
  const rows = (v: { retire: { steps: { key: string; label: string; state: string; note: string }[] } }) => v.retire.steps.map((x) => `${x.label}:${x.state}${x.note === "" ? "" : `:${x.note}`}`);
  const labels = ["传文件", "暂停聊天，补传改动", "Aspen 接收聊天", "移账号", "移连接"];
  const at = (i: number, now: string) => labels.map((l, j) => `${l}:${j < i ? "done" : j === i ? now : "todo"}`);
  const sending = retiring("sending", { cancellable: true });
  assert.deepEqual(rows(sending), [`传文件:now:1.5 MB / 3.2 GB`, ...at(0, "now").slice(1)]);
  assert.equal(sending.retire.cancellable, true);
  assert.equal(sending.retire.stopped, false);
  assert.equal(sending.retire.done, false);
  assert.equal(sending.retire.to, B);
  assert.equal(sending.retire.toName, "Aspen");
  assert.equal(sending.retire.left, null);
  assert.equal(sending.canRetire, false, "one recorded");
  assert.ok("ok" in conform("StationCopies", sending), JSON.stringify(conform("StationCopies", sending)));
  for (const [i, step] of ["quiet", "handing", "accounts", "connects"].entries()) {
    const v = retiring(step);
    assert.deepEqual(rows(v), at(i + 1, "now"), step);
    assert.equal(v.retire.stopped, true, step);
    assert.equal(v.retire.done, false, step);
  }
  const done = retiring("done");
  assert.deepEqual(rows(done), labels.map((l) => `${l}:done`));
  assert.equal(done.retire.done, true);
  assert.equal(done.retire.stopped, false);
  // accounts' step only where they move (its home workspace), or where the station is at it
  assert.deepEqual(rows(retiring("connects", { home: false })), at(4, "now").filter((r) => !r.startsWith("移账号")).map((r) => r.replace("移连接:todo", "移连接:now")));
  assert.deepEqual(rows(retiring("accounts", { home: undefined })), at(3, "now"));
  // a failure marks its step, why in words; tried again and let go of as its station says, by one who manages it
  const why: Record<string, string> = {
    offline: "连不上 Aspen",
    full: "磁盘满了",
    old: "Aspen 的版本太旧，先更新它",
    failed: "Aspen 放入聊天时出错",
    error: "出错了，详情在 station 日志里",
  };
  for (const [reason, note] of Object.entries(why)) {
    const v = retiring("handing", { error: "station said so", reason, retriable: true, cancellable: true });
    assert.deepEqual(v.retire.steps[2], { key: "handing", label: "Aspen 接收聊天", state: "failed", note }, reason);
    assert.deepEqual(v.retire.steps.map((x: { state: string }) => x.state), ["done", "done", "failed", "todo", "todo"], reason);
    assert.equal(v.retire.retriable, true, reason);
    assert.equal(v.retire.cancellable, true, reason);
    assert.equal(v.retire.done, false, reason);
    assert.ok("ok" in conform("StationCopies", v), JSON.stringify(conform("StationCopies", v)));
  }
  assert.equal(retiring("sending", { cancellable: true }, false).retire.cancellable, false, "not let go of by one who does not manage it");
  assert.equal(retiring("handing", { error: "x", reason: "offline", retriable: true }, false).retire.retriable, false, "nor tried again");
  assert.equal(retiring("sending", { toName: "" }).retire.toName, B.slice(0, 8), "one with no name by its id");
  // the accounts that could not go: a row of their own, how many and which, done or not
  const left = retiring("done", { accountsLeft: [{ id: "p1", name: "cuesurf5@proton.me", error: "x" }, { id: "p2", name: "Kimi key", error: "y" }] });
  assert.deepEqual(left.retire.left, { label: "2 个账号没移过去", note: "cuesurf5@proton.me 和 Kimi key：需要在 Aspen 上重新添加" });
  assert.equal(left.retire.done, true);
  assert.deepEqual(retiring("connects", { home: false, accountsLeft: [{ id: "p1", name: "", error: "x" }] }).retire.left?.label, "1 个账号没移过去");
  assert.ok("ok" in conform("StationCopies", left), JSON.stringify(conform("StationCopies", left)));
});

test("a station taking retired ones' chats in: a row for each, whose and where it stands at each step, and one that failed", () => {
  const base = { to: 7, chats: 12, keepers: [keeper(A, "Cedar", {})], empty: false, manage: true, formerly: [] };
  const step = (s: string, o: Record<string, unknown> = {}) => ({ origin: C, name: "Old Mac", step: s, error: null, ...o });
  const v = copiesShown({ ...base, taking: [step("coming"), step("placing"), step("gits"), step("copy"), step("restart"), step("failed", { error: "x" }), step("placing", { error: "x" }), { origin: A, name: "", step: "coming", error: null }] }, c);
  assert.deepEqual(v.taking.map((x: { name: string; line: string; level: string }) => [x.name, x.line, x.level]), [
    ["Old Mac", "正在接收聊天", "ok"],
    ["Old Mac", "正在放入聊天", "ok"],
    ["Old Mac", "正在重建工作目录", "ok"],
    ["Old Mac", "正在放入工作目录里的文件", "ok"],
    ["Old Mac", "聊天已就绪，这台重启后接上", "ok"],
    ["Old Mac", "没接收成：出错了，详情在 station 日志里", "amber"],
    ["Old Mac", "没接收成：出错了，详情在 station 日志里", "amber"],
    [A.slice(0, 8), "正在接收聊天", "ok"],
  ]);
  assert.equal(v.taking[0].origin, C);
  assert.equal(v.canRetire, true, "taking others' in, it may be retired itself");
  assert.ok("ok" in conform("StationCopies", v), JSON.stringify(conform("StationCopies", v)));
});
