// The Rust core's jobs.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { holdLanguage } from "../src/i18n.ts";
import { ago, chatJobs, type From, LONG, log, longJobs, longNext, nextChange, remoteOwner, shown, span } from "../src/jobs.ts";

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
  assert.deepEqual([ago(NOW - 2_000, NOW), ago(NOW - 12_000, NOW), ago(NOW - 30 * 3_600_000, NOW), ago(NOW - 3 * 86_400_000, NOW)], ["刚刚", "12 秒前", "1 天前", "3 天前"]);
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
  assert.deepEqual([died.tone, texts(died)], ["fail", "意外退出 · 退出码 2 · 2 小时前"]);
  const old = shown(job("w", { state: "exited", endedAt: NOW - 2 * NEWS }), c());
  assert.equal(texts(old), "意外退出 · 被信号结束 · 2 天前");
  const done = shown(job("w", { state: "exited", exitCode: 0, endedAt: NOW - 10_000 }), c());
  assert.deepEqual([done.tone, texts(done)], ["off", "已结束 · 10 秒前"]);
  const up = shown(job("s", { port: 4817, startedAt: NOW - 7_200_000 }), c());
  assert.deepEqual([up.tone, texts(up), up.open], ["up", "在线 · 2 小时", true]);
  const again = shown(job("s", { port: 4817, state: "exited", restarts: 2 }), c());
  assert.deepEqual([again.tone, texts(again)], ["restart", "正在重启 · 第 2 次"]);
});

test("a_chats_jobs_put_what_matters_first_and_leave_out_those_over", () => {
  const chat = {
    agents: [
      { jobs: [job("old", { state: "stopped", startedAt: NOW - 90_000, endedAt: NOW - 80_000 }), job("w"), job("done", { state: "exited", exitCode: 0, endedAt: NOW - 1_000 })] },
      { jobs: [job("s", { session: "b", port: 1, startedAt: NOW - 5_000 }), job("r", { session: "b", port: 2, state: "exited" }), job("x", { session: "b", port: 3, state: "failed", endedAt: NOW - 1_000 }), job("y", { session: "b", port: 4, state: "failed", startedAt: NOW - 2 * NEWS, endedAt: NOW - NEWS - 1 }), job("died", { state: "exited", exitCode: 1, endedAt: NOW - 1_000 }), job("lost", { state: "failed", endedAt: NOW - 1_000 })] },
    ],
  };
  const [v, next] = chatJobs(chat, c());
  assert.deepEqual(v.jobs.map((j: J) => j.id), ["x", "r", "w", "s"], "tasks that ended, however they ended, and services that died over a day ago are left out");
  assert.deepEqual([v.alarm, v.servicesNote, v.jobsNote], ["fail", "1 个在线，1 个在重启", "1 个运行中"]);
  assert.equal(v.allText, "全部 4 个");
  assert.ok(next <= 1000);
  const [none, next2] = chatJobs({ agents: [] }, c());
  assert.deepEqual([none.alarm, none.jobs, next2], [null, [], Infinity]);
});

test("a_chat_jobs_summary_keeps_the_button_and_alarm_without_preparing_the_jobs_page", () => {
  const chat = { agents: [{ jobs: [
    job("failed", { port: 3, state: "failed", endedAt: NOW - NEWS + 5_000 }),
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
  const [over] = chatJobs({ agents: [{ jobs: [job("old", { state: "stopped" }), job("done", { state: "exited", exitCode: 0 }), job("died", { state: "exited", exitCode: 1, endedAt: NOW - 1_000 })] }] }, c(), true);
  assert.equal(over.hasJobs, false, "no button for jobs that are all over");
  const [empty, never] = chatJobs({ agents: [] }, c(), true);
  assert.deepEqual([empty.hasJobs, empty.alarm, never], [false, null, Infinity]);
});

test("those_up_long_are_grouped_oldest_first_with_where_they_are", () => {
  const st = (name: string | null, jobs: J[]): [string, string | null, J[]] => ["w/s1", name, jobs];
  const v = longJobs(
    [
      st("orchard", [
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
  assert.deepEqual([g[1].head, g[1].jobs[0].id, g[1].jobs[0].whereText, g[1].jobs[0].age], ["长时间运行的后台任务 · 2", "j1", "orchard · 对话", "3 小时"]);
  assert.equal(g[1].jobs[1].whereText, "orchard · 修登录 · 已归档");
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

test("simulators_and_peoples_views_up_long_are_listed_with_how_each_is_stopped", () => {
  const view = (id: string, patch: J = {}): J => ({ id, name: "Peng", device: "MacBook", at: NOW - 2 * LONG, may: true, ...patch });
  const screens: J[] = [
    { id: "simulator:A", title: "Demo iPhone · iOS 27.2", since: NOW - 3 * LONG, closable: true, views: [view("v1"), view("v2", { here: true }), view("v3", { agent: true, may: false }), view("v4", { at: NOW - 60_000 })] },
    { id: "android:emulator-5580", title: "fold · Android 16", since: NOW - 2 * LONG, closable: true },
    { id: "simulator:B", title: "new", since: NOW - 60_000, closable: true },
    // A phone (no `since`), the desktop (not closable), one the viewer may not close
    { id: "android:R5", title: "Pixel", closable: false },
    { id: "desktop", title: "Mac", views: [view("v5", { may: false })] },
    { id: "simulator:C", title: "theirs", since: NOW - 3 * LONG },
  ];
  const v = longJobs([], c(), undefined, undefined, [["w/s1", "orchard", screens]]);
  const [sims, views] = v.groups;
  assert.deepEqual([sims.key, sims.head, views.key, views.head], ["simulators", "长时间开着的模拟器 · 2", "views", "长时间开着的远程连接 · 1"]);
  assert.deepEqual(sims.jobs.map((j: J) => [j.id, j.whereText, j.age, j.stop]), [
    ["screen:simulator:A", "orchard · iOS 模拟器", "3 小时", { call: "screen.close", screen: "simulator:A", word: "关闭" }],
    ["screen:android:emulator-5580", "orchard · 安卓模拟器", "2 小时", { call: "screen.close", screen: "android:emulator-5580", word: "关闭" }],
  ]);
  assert.deepEqual([views.jobs[0].id, views.jobs[0].name, views.jobs[0].whereText, views.jobs[0].stop], ["view:simulator:A/v1", "Demo iPhone · iOS 27.2", "orchard · Peng · MacBook", { call: "screen.endView", screen: "simulator:A", view: "v1", word: "断开" }]);
  assert.deepEqual(v.ids, ["w/s1/screen:simulator:A", "w/s1/screen:android:emulator-5580", "w/s1/view:simulator:A/v1"]);
  assert.equal(v.lit, true);
  // Asked again as the next is up an hour: simulator:B's, a minute in; v4 the same.
  assert.equal(longNext([], [["w/s1", null, screens]], NOW), LONG - 60_000);
  assert.equal(longNext([["w/s1", null, [job("j", { startedAt: NOW - LONG + 5_000 })]]], [], NOW), 5_000);
  assert.equal(longNext([], [], NOW), null);
});

test("a_task_another_stations_chat_runs_is_in_that_chat", () => {
  assert.deepEqual(remoteOwner("remote:w:cedar:chat:c-1"), { station: "w/cedar", session: "chat:c-1" });
  assert.equal(remoteOwner("chat:c-1"), null);
  const chat = { id: "chat:c-1", title: "编译器", archived: false, station: "w/cedar" };
  const from = (session: string): From | null =>
    session === "remote:w:cedar:chat:c-1" ? { name: "cedar", chat } : session === "remote:w:cedar:chat:c-2" ? { name: "cedar", chat: null } : null;
  const ran = (session: string) => job(session, { session, startedAt: NOW - 2 * LONG });
  const v = longJobs([["w/orchard", "orchard", [ran("remote:w:cedar:chat:c-1"), ran("remote:w:cedar:chat:c-2"), ran("a")]]], c(), from);
  const [known, unknown, own] = v.groups[0].jobs;
  assert.deepEqual([known.whereText, known.chat, known.station], ["orchard · 编译器 · 来自 cedar", chat, "w/orchard"]);
  assert.deepEqual([unknown.whereText, unknown.chat], ["orchard · 对话 · 来自 cedar", undefined]);
  assert.equal(own.whereText, "orchard · 不属于任何对话");
});

test("a_logs_last_line_and_when", () => {
  let v: J = { text: "a\nbuilt ok\n", outputAt: NOW - 3_000, state: "running" };
  v = log(v, c());
  assert.deepEqual([v.last, v.said], ["built ok", "最后输出 · 刚刚"]);
  let empty: J = { text: "" };
  empty = log(empty, c());
  assert.deepEqual([empty.last, empty.said, empty.lines], [undefined, undefined, []]);
});

test("a_logs_lines_each_by_its_number_its_runs_and_nothing_else_of_it", () => {
  // (numbered from what the link kept, `from`; an empty line no runs; the text, the runs whole and `from` not sent)
  const v = log({ text: "\u001b[32mok\u001b[39m one\n\n  two  ", outputAt: NOW - 3_000, from: 40 }, c());
  assert.deepEqual(v.lines, [
    { n: 40, runs: [{ text: "ok", fg: "2" }, { text: " one" }] },
    { n: 41, runs: [] },
    { n: 42, runs: [{ text: "  two  " }] },
  ]);
  assert.deepEqual(Object.keys(v).sort(), ["last", "lines", "outputAt", "said"]);
  assert.equal(v.last, "two");
  // Asked for its last line alone (a job's row): that and when, no lines.
  const row = log({ text: "two", outputAt: NOW - 3_000, from: 7 }, c(), 1);
  assert.deepEqual(row, { outputAt: NOW - 3_000, last: "two", said: "最后输出 · 刚刚" });
  // (shaped as it goes out)
  assert.ok("ok" in conform("JobLogView", v), JSON.stringify(conform("JobLogView", v)));
  // Shown again (held inside another value and put out a second time): as it was, its lines kept.
  assert.equal(log(v, c()), v);
  assert.deepEqual(log(row, c(), 1), row);
});
