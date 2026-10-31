// The Rust core's views/admin.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { feedback, list, overview, user, workspace } from "../src/views/admin.ts";
import { relays } from "../src/views/admin-relays.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const NOW = 1_790_000_000;
const DAY = 86_400;

const users = (): J => ({
  users: [
    { sub: "a", email: "ann@x.io", name: "Ann", picture: "", created_at: NOW - 2 * DAY, last_seen: NOW - 3600, admission: "code", workspaces: [{ id: "w1", name: "产品", role: "owner" }], beta: false, may_create: true, creator: true },
    { sub: "b", email: "bob@y.io", name: "", picture: "", created_at: NOW - 40 * DAY, last_seen: NOW - 35 * DAY, admission: null, workspaces: [], beta: true, may_create: false, blocked: true },
    { sub: "c", email: "cat@x.io", name: "Cat", picture: "", created_at: NOW - 10 * DAY, last_seen: null, admission: "invitation", workspaces: [{ id: "w1", name: "产品", role: "member" }] },
  ],
});
const workspaces = (): J => ({
  workspaces: [
    {
      id: "w1", name: "产品", created_at: NOW - 2 * DAY, created_by: { sub: "a", email: "ann@x.io", name: "Ann", picture: "" }, seats: 2,
      members: [{ sub: "a", email: "ann@x.io", name: "Ann", picture: "", role: "owner", added_at: 1, last_seen: NOW - 3600 }, { sub: "c", email: "cat@x.io", name: "Cat", picture: "", role: "member", added_at: 2 }],
      stations: [{ id: "s1", name: "studio", version: "0.1.1212", last_seen: NOW - 60 }, { id: "s2", name: "nas", version: "0.1.1104", last_seen: null }], invitations: [],
    },
    { id: "w2", name: "设计", created_at: NOW - 5 * DAY, created_by: null, members: [], stations: [], invitations: [{ id: "i", role: "member", email: null, inviter: "Ann", expires_at: NOW + DAY }] },
  ],
});
const reports = (): J => ({
  feedback: [
    {
      id: "F2", number: 2, channel: "beta", station: { id: "s1", name: "studio" }, workspace: { id: "w1", name: "产品" }, account: null,
      title: "发送后消息消失", body: "## 步骤\n1. 发一条", area: "web", reporter: "Ann (Slack)", context: { version: "0.1.1212", session: "ember:c-1", extra: { a: 1 } },
      logs: "line 1\nline 2", status: "new", created_at: NOW - 60, updated_at: NOW - 60,
    },
    {
      id: "F1", number: 1, channel: "stable", station: null, workspace: null, account: { sub: "a", email: "ann@x.io", name: "" },
      title: "图标糊了", body: "看着糊", area: "android", reporter: "", context: null, logs: null, status: "fixed", created_at: NOW - DAY, updated_at: NOW,
    },
  ],
});
const ids = (v: J) => v.rows.map((r: J) => r.id);
const count = (v: J, filter: string) => v.filters.find((f: J) => f.id === filter).count;

test("users_are_found_filtered_and_sorted", () => {
  const all = list("users", users(), "", null, null, null, NOW);
  assert.deepEqual(ids(all), ["a", "b", "c"]);
  assert.deepEqual([count(all, "stuck"), count(all, "blocked"), count(all, "dormant"), count(all, "new")], [1, 1, 2, 1]);
  assert.equal(all.rows[1].title, "bob@y.io");
  assert.deepEqual(all.rows[1].marks.map((m: J) => m.label), ["已封禁", "尚未加入", "测试版"]);
  assert.equal(all.rows[0].line, "ann@x.io · 产品");
  const found = list("users", users(), "X.IO 产品", "all", "name", null, NOW);
  assert.deepEqual([ids(found), count(found, "stuck")], [["a", "c"], 0]);
  const page = list("users", users(), "", "dormant", "created", 1, NOW);
  assert.deepEqual([ids(page), page.more, page.found], [["c"], true, 2]);
});

test("emails_given_rights_before_a_sign_in_are_listed_with_the_users_and_have_a_page", () => {
  const v = { ...users(), pending: [{ email: "dan@z.io", beta: true, may_create: true, added_at: NOW - DAY }, { email: "eve@z.io", beta: false, may_create: false, added_at: NOW - 3 * DAY }] };
  const all = list("users", v, "", null, null, null, NOW);
  assert.equal(all.total, 5);
  // Never seen, they sort among those never seen, by when they were added.
  assert.deepEqual(ids(all), ["a", "b", "email:dan@z.io", "email:eve@z.io", "c"]);
  const dan = all.rows[2];
  assert.deepEqual([dan.title, dan.line, dan.marks.map((m: J) => m.label), dan.last_seen], ["dan@z.io", "首次登录后开通：测试版、标准版", ["未登录", "测试版"], null]);
  assert.equal(all.rows[3].line, "首次登录后开通：尚未开通任何资格");
  // Nothing an account did is said of them; what they were given is.
  assert.deepEqual([count(all, "stuck"), count(all, "dormant"), count(all, "new"), count(all, "active")], [1, 2, 1, 1]);
  assert.deepEqual([count(all, "pending"), count(all, "beta"), count(all, "creators")], [2, 2, 2]);
  assert.deepEqual(ids(list("users", v, "dan", null, null, null, NOW)), ["email:dan@z.io"]);
  // Nor are they users in the overview.
  assert.equal(overview(v, workspaces(), { codes: [] }, undefined, NOW, 0).stats[0].value, 3);

  const page = user("email:dan@z.io", v, workspaces(), undefined, NOW);
  assert.deepEqual([page.pending, page.email, page.admission, page.beta, page.mayCreate, page.mayCreateFixed, page.blocked, page.workspaces], [true, "dan@z.io", "未登录", true, true, false, null, []]);
  assert.throws(() => user("email:nobody@z.io", v, workspaces(), undefined, NOW));
  // From a cloud from before it, there are none.
  assert.equal(list("users", users(), "", null, null, null, NOW).total, 3);
});

test("a_code_with_the_test_channel_says_so", () => {
  const v = list("invite-codes", { codes: [{ code: "AAAA-BBBB-CCCC", note: "", beta: true, created_at: NOW - 60, expires_at: NOW + DAY, revoked_at: null, used_at: null, used_by: null, workspace: null }] }, "", null, null, null, NOW);
  assert.deepEqual(v.rows[0].marks.map((m: J) => m.label), ["可用", "测试版"]);
});

test("workspaces_say_what_is_off", () => {
  const all = list("workspaces", workspaces(), "", null, null, null, NOW);
  assert.deepEqual(ids(all), ["w1", "w2"]);
  assert.deepEqual([count(all, "bare"), count(all, "outdated"), count(all, "full"), count(all, "invited")], [1, 1, 1, 1]);
  assert.equal(all.rows[0].state, "online");
  assert.equal(all.rows[1].line, "前成员 创建 · 0 人 · 0 台 station");
  assert.deepEqual(ids(list("workspaces", workspaces(), "nas", null, null, null, NOW)), ["w1"]);
});

test("a_users_page_counts_their_workspaces", () => {
  let page = user("a", users(), workspaces(), null, NOW);
  assert.equal(page.workspaces[0].line, "Owner · 2 人 · 2 台 station");
  assert.deepEqual([page.mayCreate, page.mayCreateFixed], [true, true]);
  page = user("b", users(), workspaces(), null, NOW);
  assert.deepEqual([page.admission, page.mayCreateFixed, page.blocked], ["尚未加入", false, true]);
  assert.throws(() => user("z", users(), workspaces(), null, NOW));
});

test("a_workspaces_page_has_its_people_and_stations", () => {
  const page = workspace("w1", workspaces(), users(), NOW);
  assert.equal(page.people, "2 / 2");
  assert.deepEqual([page.stations[1].state, page.stations[1].outdated], ["error", true]);
  assert.equal(page.members[1].last_seen, null);
  assert.equal(page.members[0].role, "Owner");
});

test("an unlimited station count is shown without a cap and the admin can set one", () => {
  const input = workspaces();
  input.workspaces[0].stations_unlimited = true;
  let page = workspace("w1", input, users(), NOW);
  assert.equal(page.stationCount, "2");
  assert.deepEqual(page.limits, { members: 2, stations: null });
  delete input.workspaces[0].stations_unlimited;
  input.workspaces[0].station_seats = 64;
  page = workspace("w1", input, users(), NOW);
  assert.equal(page.stationCount, "2 / 64");
  assert.deepEqual(page.limits, { members: 2, stations: 64 });
  delete input.workspaces[0].station_seats;
  assert.equal(workspace("w1", input, users(), NOW).limits, null, "an older cloud gives no station limit");
});

test("the_overview_points_at_lists", () => {
  let v = overview(users(), workspaces(), { codes: [] }, null, NOW, 480);
  assert.equal(v.stats[0].value, 3);
  assert.equal(v.weeks.length, 12);
  assert.equal(v.weeks[11].count, 1);
  assert.deepEqual(v.todo.map((x: J) => [x.list, x.filter]), [["users", "stuck"], ["workspaces", "bare"], ["workspaces", "stale"], ["workspaces", "outdated"]]);
  v = overview(users(), workspaces(), { codes: [] }, reports(), NOW, 480);
  assert.deepEqual([v.todo[0].text, v.todo[0].list, v.todo[0].filter], ["1 个新反馈", "feedback", "new"]);
});

test("bug_reports_are_listed_by_status_and_channel", () => {
  const all = list("feedback", reports(), "", null, null, null, NOW);
  assert.deepEqual(ids(all), ["F2", "F1"]);
  assert.deepEqual([count(all, "new"), count(all, "fixed"), count(all, "beta"), count(all, "stable")], [1, 1, 1, 1]);
  assert.equal(all.rows[0].number, "FB-2");
  assert.equal(all.rows[0].line, "Web · 产品 · studio · Ann (Slack)");
  assert.equal(all.rows[1].line, "Android · ann@x.io");
  assert.deepEqual(all.rows[0].marks.map((m: J) => m.label), ["新反馈", "测试版"]);
  assert.deepEqual(ids(list("feedback", reports(), "fb-1", null, null, null, NOW)), ["F1"]);
  assert.deepEqual(ids(list("feedback", reports(), "STUDIO 步骤", null, null, null, NOW)), ["F2"]);
  assert.deepEqual(ids(list("feedback", reports(), "", "fixed", null, null, NOW)), ["F1"]);
});

test("a_bug_reports_page_has_all_of_it_in_text_too", () => {
  let page = feedback("F2", reports());
  assert.deepEqual([page.number, page.status, page.channelLabel], ["FB-2", "new", "测试版"]);
  assert.equal(page.statuses.length, 4);
  const context = page.context.map((c: J) => [c.key, c.value]);
  assert.ok(context.some(([k, v]: J) => k === "version" && v === "0.1.1212") && context.some(([k, v]: J) => k === "extra" && v === '{"a":1}'), JSON.stringify(context));
  const text: string = page.text;
  assert.ok(text.startsWith("FB-2 发送后消息消失\n"), text);
  for (const part of ["渠道: 测试版 (beta)", "Station: studio (s1)", "Workspace: 产品 (w1)", "反馈人: Ann (Slack)", "## 步骤", "session: ember:c-1", "```\nline 1\nline 2\n```"]) assert.ok(text.includes(part), `${part} in ${text}`);
  page = feedback("F1", reports());
  assert.deepEqual([page.logs, page.context.length, page.account.title], [null, 0, "ann@x.io"]);
  assert.ok(!page.text.includes("## 日志"));
  assert.throws(() => feedback("F9", reports()));
  assert.deepEqual(list("feedback", {}, "", null, null, null, NOW).rows, []);
});

test("the_relays_page_says_each_relays_load_now_and_over_the_range", () => {
  // A whole hour in UTC, so the day's buckets fall on local hours (UTC+8).
  const now = NOW - (NOW % 3600);
  const day = (f: (i: number) => number | null) => ({ start: now - 287 * 300, step: 300, sent: Array.from({ length: 288 }, (_, i) => f(i)), recv: Array.from({ length: 288 }, () => 1000), open: Array.from({ length: 288 }, (_, i) => (i === 10 ? 71 : 3)), dropped: [] });
  const week = { start: now - 167 * 3600, step: 3600, sent: Array.from({ length: 168 }, () => 10), recv: [], open: [], dropped: [] };
  const answer = {
    relays: [
      { url: "https://app.still.fail", name: "Cloudflare", at: now - 30, now: { sent: 14_336, recv: 2048, dropped: 0.021, rx: null, tx: null }, open: 71, load1: null, today: { bytes: 4.5 * 1024 ** 3, frames: 1000 }, limits: { bytes: 5 * 1024 ** 3, frames: 20_000_000 }, day: day((i) => (i < 5 ? null : 2048)), week },
      { url: "https://47.76.247.168", name: "香港", at: now - 3600, now: null, open: null, load1: null, today: { bytes: 0, frames: 0 }, day: day(() => null), week },
      { url: "https://39.105.157.122", name: "北京", at: now - 10, now: { sent: 0, recv: 0, dropped: 0.3, rx: 50_000, tx: 64_000 }, open: 2, load1: 0.04, today: { bytes: 0, frames: 0 }, day: day(() => 0), week },
      { url: "https://relay.example", name: "深圳", at: null, now: null, open: null, load1: null, today: { bytes: 0, frames: 0 }, day: day(() => null), week },
    ],
  };
  const v = relays(answer, null, now, 480);
  assert.equal(v.range, "day");
  assert.deepEqual(v.ranges.map((r: J) => r.label), ["24 小时", "7 天"]);
  const [cf, hk, bj, sz] = v.relays;
  assert.deepEqual([cf.state, hk.state, bj.state, sz.state], ["online", "offline", "online", "error"]);
  assert.deepEqual([cf.seen, hk.seen, sz.seen], ["刚刚更新", "1 小时前更新", "暂无数据"]);
  // Never heard from: nothing but that.
  assert.deepEqual([sz.numbers, sz.charts, sz.ticks], [[], [], []]);
  assert.deepEqual(cf.numbers, [
    { label: "发送", value: "14 KB/s" },
    { label: "接收", value: "2.0 KB/s" },
    { label: "在线连接", value: "71" },
    { label: "丢包率", value: "2.1%" },
    { label: "今日用量", value: "4.5 GB / 5.0 GB · 90%", tone: "amber" },
  ]);
  assert.deepEqual(hk.numbers.map((n: J) => n.value), ["–", "–", "–", "–"]);
  assert.deepEqual(bj.numbers.slice(3), [{ label: "丢包率", value: "30.0%", tone: "red" }, { label: "网卡", value: "出 63 KB/s · 入 49 KB/s" }, { label: "负载", value: "0.04" }]);
  assert.deepEqual(cf.charts.map((c: J) => [c.id, c.peak, c.series.map((s: J) => s.id)]), [["rate", "峰值 2.0 KB/s", ["sent", "recv"]], ["open", "峰值 71", ["open"]]]);
  assert.equal(cf.charts[0].series[0].values[0], null);
  // Every six hours, local: four marks a day.
  assert.equal(cf.ticks.length, 4);
  assert.ok(cf.ticks.every((tick: J) => ["00:00", "06:00", "12:00", "18:00"].includes(tick.label)));
  const w = relays(answer, "week", now, 480);
  assert.equal(w.range, "week");
  assert.equal(w.relays[0].charts[0].series[0].values.length, 168);
  assert.ok(w.relays[0].ticks.every((tick: J) => /^\d+\/\d+$/.test(tick.label)));
});
