// The Rust core's jobs.rs and footprint.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import * as fp from "../src/footprint.ts";
import { holdLanguage } from "../src/i18n.ts";
import { ago, chatJobs, type From, LONG, log, longJobs, nextChange, remoteOwner, shown, span } from "../src/jobs.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const NOW = 1_790_467_200_000;
const NEWS = 24 * 3_600_000;
const c = () => ({ now: NOW, offsetMin: 480 });
const job = (id: string, patch: J = {}): J => ({ id, session: "a", name: id, state: "running", port: null, startedAt: NOW - 3_000, ...patch });
const texts = (v: J) => v.meta.map((p: J) => p.text).join("");

test("times_in_words_and_when_they_change", () => {
  assert.deepEqual([span(12_000), span(4 * 60_000 + 59_000), span(3 * 3_600_000), span(2 * 86_400_000)], ["12 秒", "4 分钟", "3 小时", "2 天"]);
  assert.deepEqual([ago(NOW - 2_000, NOW), ago(NOW - 12_000, NOW), ago(NOW - 30 * 3_600_000, NOW), ago(NOW - 3 * 86_400_000, NOW)], ["刚刚", "12 秒前", "昨天", "3 天前"]);
  assert.deepEqual([nextChange(12_000), nextChange(250_000)], [500, 49_500]);
});

test("a_job_is_shown_by_its_dot_its_word_and_its_line", () => {
  const live = shown(job("w"), c());
  assert.deepEqual([live.tone, live.word, texts(live)], ["live", "运行中", "运行中 · 3 秒"]);
  assert.equal(live.meta[0].kind, "word");
  const said = shown(job("w", { notices: [{ at: NOW - 60_000, text: "CI 绿了" }], outputAt: NOW - 1_000 }), c());
  assert.deepEqual([texts(said), said.meta[0].kind], ["CI 绿了 · 1 分钟前", "notice"]);
  assert.deepEqual([said.notices[0].ago, said.notices[0].clock, said.detail], ["1 分钟前", "07:59", "运行中 · 3 秒 · 1 条通知"]);
  const quiet = shown(job("w", { outputAt: NOW - 20_000 }), c());
  assert.deepEqual([texts(quiet), quiet.outputSaid], ["暂无通知 · 最后输出 20 秒前", "最后输出 · 20 秒前"]);
  const died = shown(job("w", { state: "exited", exitCode: 2, endedAt: NOW - 7_200_000 }), c());
  assert.deepEqual([died.tone, texts(died), died.ended, died.current], ["fail", "意外退出 · 退出码 2 · 2 小时前", true, true]);
  const old = shown(job("w", { state: "exited", endedAt: NOW - 2 * NEWS }), c());
  assert.deepEqual([texts(old), old.current], ["意外退出 · 被信号结束 · 2 天前", false]);
  const done = shown(job("w", { state: "exited", exitCode: 0, endedAt: NOW - 10_000 }), c());
  assert.deepEqual([done.tone, texts(done)], ["off", "已结束 · 10 秒前"]);
  const up = shown(job("s", { port: 4817, startedAt: NOW - 7_200_000 }), c());
  assert.deepEqual([up.tone, texts(up), up.open, up.ended], ["up", "在线 · 2 小时", true, false]);
  const again = shown(job("s", { port: 4817, state: "exited", restarts: 2 }), c());
  assert.deepEqual([again.tone, texts(again), again.ended], ["restart", "正在重启 · 第 2 次", false]);
});

test("a_chats_jobs_put_what_matters_first_and_say_how_many", () => {
  const chat = {
    agents: [
      { jobs: [job("old", { state: "stopped", startedAt: NOW - 90_000, endedAt: NOW - 80_000 }), job("w")] },
      { jobs: [job("s", { session: "b", port: 1, startedAt: NOW - 5_000 }), job("r", { session: "b", port: 2, state: "exited" }), job("x", { session: "b", state: "failed", endedAt: NOW - 1_000 })] },
    ],
  };
  const [v, next] = chatJobs(chat, c());
  assert.deepEqual(v.jobs.map((j: J) => j.id), ["x", "r", "w", "s", "old"]);
  assert.deepEqual([v.alarm, v.servicesNote, v.jobsNote], ["fail", "1 个在线，1 个在重启", "1 个运行中"]);
  assert.deepEqual([v.current, v.ended, v.clear], [4, 2, ["b", "a"]]);
  assert.deepEqual([v.allText, v.clearText, v.hiddenText], ["全部 5 个", "清除 2 个已结束的", "另有 1 个已停止或结束"]);
  assert.ok(next <= 1000);
  const [none, next2] = chatJobs({ agents: [] }, c());
  assert.deepEqual([none.alarm, none.jobs, next2], [null, [], Infinity]);
});

test("a_chat_jobs_summary_keeps_the_button_and_alarm_without_preparing_the_jobs_page", () => {
  const chat = { agents: [{ jobs: [
    job("failed", { state: "failed", endedAt: NOW - NEWS + 5_000 }),
    job("restarting", { state: "exited", port: 1 }),
    job("old", { state: "stopped" }),
  ] }] };
  const [full] = chatJobs(chat, c());
  const [brief, next] = chatJobs(chat, c(), true);
  assert.equal(brief.hasJobs, full.jobs.length > 0);
  assert.equal(brief.alarm, full.alarm);
  assert.deepEqual(brief.jobs, [], "the unopened jobs page is not formatted");
  assert.equal(next, 5_000, "the alarm is checked again when the failure is no longer recent");
  const [later] = chatJobs(chat, { ...c(), now: NOW + 5_000 }, true);
  assert.equal(later.alarm, "restart");
  const [empty, never] = chatJobs({ agents: [] }, c(), true);
  assert.deepEqual([empty.hasJobs, empty.alarm, never], [false, null, Infinity]);
});

test("those_up_long_are_grouped_oldest_first_with_where_they_are", () => {
  const st = (name: string | null, jobs: J[]): [string, string | null, J[]] => ["w/s1", name, jobs];
  const v = longJobs(
    [
      st("studio", [
        job("new", { startedAt: NOW - 60_000 }),
        job("j2", { startedAt: NOW - 2 * LONG, chat: { id: "7", title: "修登录", archived: true } }),
        job("j1", { startedAt: NOW - 3 * LONG, chat: { id: "8", title: "", archived: false } }),
      ]),
      st(null, [job("s", { port: 1, startedAt: NOW - LONG })]),
    ],
    c(),
  );
  const g = v.groups;
  assert.deepEqual([g[0].key, g[0].head, g[0].jobs[0].whereText], ["services", "长时间运行的网页服务 · 1", "不属于任何对话"]);
  assert.deepEqual([g[1].head, g[1].jobs[0].id, g[1].jobs[0].whereText, g[1].jobs[0].age], ["长时间运行的后台任务 · 2", "j1", "studio · 对话", "3 小时"]);
  assert.equal(g[1].jobs[1].whereText, "studio · 修登录 · 已归档");
  assert.deepEqual(longJobs([st(null, [job("new")])], c()), { groups: [], lit: false, ids: [] });
  const watch = job("w", { startedAt: NOW - 5 * LONG, watch: true });
  assert.deepEqual(longJobs([st(null, [watch])], c()), { groups: [], lit: false, ids: [] });
  assert.equal(shown(watch, c()).word, "监控中");
});

test("those_up_long_light_the_bell_until_it_has_shown_them", () => {
  const up = (id: string) => job(id, { port: 1, startedAt: NOW - 2 * LONG });
  const st: [string, string | null, J[]][] = [["w/s1", null, [up("a"), up("b")]]];
  const v = longJobs(st, c());
  assert.deepEqual([v.lit, v.ids], [true, ["w/s1/a", "w/s1/b"]]);
  assert.equal(longJobs(st, c(), undefined, { on: true, seen: new Set(v.ids) }).lit, false, "both shown");
  assert.equal(longJobs(st, c(), undefined, { on: true, seen: new Set(["w/s1/a"]) }).lit, true, "a new one since");
  assert.equal(longJobs(st, c(), undefined, { on: false, seen: new Set() }).lit, false, "the bell not lit by them");
  assert.equal(longJobs(st, c(), undefined, { on: false, seen: new Set() }).groups[0].jobs.length, 2, "still listed");
});

test("a_task_another_stations_chat_runs_is_in_that_chat", () => {
  assert.deepEqual(remoteOwner("remote:w:ccvm:ember:c-1"), { station: "w/ccvm", session: "ember:c-1" });
  assert.equal(remoteOwner("ember:c-1"), null);
  const chat = { id: "ember:c-1", title: "编译器", archived: false, station: "w/ccvm" };
  const from = (session: string): From | null =>
    session === "remote:w:ccvm:ember:c-1" ? { name: "ccvm", chat } : session === "remote:w:ccvm:ember:c-2" ? { name: "ccvm", chat: null } : null;
  const ran = (session: string) => job(session, { session, startedAt: NOW - 2 * LONG });
  const v = longJobs([["w/studio", "studio", [ran("remote:w:ccvm:ember:c-1"), ran("remote:w:ccvm:ember:c-2"), ran("a")]]], c(), from);
  const [known, unknown, own] = v.groups[0].jobs;
  assert.deepEqual([known.whereText, known.chat, known.station], ["studio · 编译器 · 来自 ccvm", chat, "w/studio"]);
  assert.deepEqual([unknown.whereText, unknown.chat], ["studio · 对话 · 来自 ccvm", undefined]);
  assert.equal(own.whereText, "studio · 不属于任何对话");
});

test("a_logs_last_line_and_when", () => {
  let v: J = { text: "a\nbuilt ok\n", outputAt: NOW - 3_000, state: "running" };
  v = log(v, c());
  assert.deepEqual([v.last, v.said], ["a\nbuilt ok", "最后输出 · 刚刚"]);
  let empty: J = { text: "" };
  empty = log(empty, c());
  assert.deepEqual([empty.last, empty.said], [undefined, undefined]);
});

// ── footprint.rs ──

const FNOW = 1_790_000_000_000;
const DAY = 86_400_000;
function raw(manage: boolean): J {
  return {
    checkedAt: FNOW - 120_000, tookMs: 9000, scanning: false, manage,
    disk: { totalBytes: 100e9, freeBytes: 8e9 },
    parts: [{ id: "chats", bytes: 8e9 }, { id: "transcripts", bytes: 1e9 }, { id: "homes", bytes: 0 }, { id: "archive", bytes: 3e8 }, { id: "repos", bytes: 3e8 }, { id: "other", bytes: 1e8 }],
    elsewhere: [{ id: "playwright", path: "~/Library/Caches/ms-playwright", bytes: 8e8 }],
    chats: [
      { key: "a", chat: { id: "a", title: "预加载", archived: false }, bytes: 3e9, rebuildBytes: 2.9e9, archived: false, lastActiveAt: FNOW - 3_600_000, state: "warm" },
      { key: "b", chat: { id: "b", title: "", archived: true }, bytes: 4e8, rebuildBytes: 1e8, archived: true, lastActiveAt: FNOW - 10 * DAY, state: "cold" },
      { key: "c", chat: { id: "c", title: "在跑", archived: false }, bytes: 3e8, rebuildBytes: 3e8, archived: false, lastActiveAt: FNOW, state: "running" },
      { key: "d", chat: { id: "d", title: "旧的", archived: true }, bytes: 1e8, rebuildBytes: 0, archived: true, lastActiveAt: FNOW - 2 * DAY, state: "cold" },
    ],
    unseen: { count: 0, bytes: 0 },
    memory: { totalBytes: 6e9, usedBytes: 5.2e9, stationBytes: 2.2e7 },
    processes: [
      { pgid: 1, runtime: "claude", rssBytes: 1.3e8, key: "a", chat: { id: "a", title: "预加载" }, state: "warm", lastActiveAt: FNOW - 3_600_000 },
      { pgid: 2, runtime: "claude", rssBytes: 1.8e8, key: "c", chat: { id: "c", title: "在跑" }, state: "running", lastActiveAt: FNOW },
      { pgid: 3, runtime: "codex", rssBytes: null, key: null, chat: null, state: null, lastActiveAt: null },
    ],
  };
}
const fc = () => ({ now: FNOW, offsetMin: 480 });
const shape = (v: unknown) => assert.ok("ok" in conform("FootprintView", v), JSON.stringify(conform("FootprintView", v)));

test("the_page_says_what_takes_the_disk_and_what_can_be_cleaned", () => {
  const v = fp.shown(raw(true), fc());
  shape(v);
  assert.equal(v.checkedText, "统计于2 分钟前");
  assert.equal(v.totalText, "9.0 GB");
  assert.equal(v.legend[2].level, "red");
  assert.deepEqual(v.actions.map((a: J) => a.id), ["rebuild", "archived", "idle"]);
  assert.deepEqual(v.actions[0].choices[0].keys, ["a", "b"]);
  const archived = v.actions[1].choices;
  assert.deepEqual(archived.map((x: J) => x.keys), [["b", "d"], ["b"]]);
  assert.equal(archived[0].confirms.length, 2);
  assert.deepEqual(v.actions[2].choices[0].keys, ["a"]);
  assert.equal(v.chats[1].title, "新对话");
  assert.deepEqual(v.chats[2].choices, []);
  assert.equal(v.chats[1].choices[1].confirms.length, 2);
  assert.equal(v.memory[2].label, "在跑");
  assert.ok(v.memory[4].label.startsWith("Codex"));
  assert.equal(v.memory[3].choice.call, "footprint.evict");
});

test("members_look_and_a_first_scan_is_waited_for", () => {
  const v = fp.shown(raw(false), fc());
  assert.deepEqual([v.actions, v.actionsNote], [[], "只有 workspace 的 owner 和管理员可以清理"]);
  assert.ok(v.chats.every((x: J) => x.choices.length === 0));
  const first = fp.shown({ scanning: true, manage: true, disk: {}, parts: [], chats: [], processes: [] }, fc());
  shape(first);
  assert.deepEqual([first.measured, first.totalText], [false, "—"]);
  let b: J = { bytes: null, scanning: true };
  b = fp.brief(b);
  assert.equal(b.text, "正在统计");
});
