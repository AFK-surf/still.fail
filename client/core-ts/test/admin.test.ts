// The Rust core's views/admin.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { feedback, list, overview, user, workspace } from "../src/views/admin.ts";

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
  assert.deepEqual(all.rows[1].marks.map((m: J) => m.label), ["已封禁", "还没进来", "测试版"]);
  assert.equal(all.rows[0].line, "ann@x.io · 产品");
  const found = list("users", users(), "X.IO 产品", "all", "name", null, NOW);
  assert.deepEqual([ids(found), count(found, "stuck")], [["a", "c"], 0]);
  const page = list("users", users(), "", "dormant", "created", 1, NOW);
  assert.deepEqual([ids(page), page.more, page.found], [["c"], true, 2]);
});

test("workspaces_say_what_is_off", () => {
  const all = list("workspaces", workspaces(), "", null, null, null, NOW);
  assert.deepEqual(ids(all), ["w1", "w2"]);
  assert.deepEqual([count(all, "bare"), count(all, "outdated"), count(all, "full"), count(all, "invited")], [1, 1, 1, 1]);
  assert.equal(all.rows[0].state, "online");
  assert.equal(all.rows[1].line, "已不在的人 创建 · 0 人 · 0 台 station");
  assert.deepEqual(ids(list("workspaces", workspaces(), "nas", null, null, null, NOW)), ["w1"]);
});

test("a_users_page_counts_their_workspaces", () => {
  let page = user("a", users(), workspaces(), null, NOW);
  assert.equal(page.workspaces[0].line, "Owner · 2 人 · 2 台 station");
  assert.deepEqual([page.mayCreate, page.mayCreateFixed], [true, true]);
  page = user("b", users(), workspaces(), null, NOW);
  assert.deepEqual([page.admission, page.mayCreateFixed, page.blocked], ["还没进来", false, true]);
  assert.throws(() => user("z", users(), workspaces(), null, NOW));
});

test("a_workspaces_page_has_its_people_and_stations", () => {
  const page = workspace("w1", workspaces(), users(), NOW);
  assert.equal(page.people, "2 / 2");
  assert.deepEqual([page.stations[1].state, page.stations[1].outdated], ["error", true]);
  assert.equal(page.members[1].last_seen, null);
  assert.equal(page.members[0].role, "Owner");
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
