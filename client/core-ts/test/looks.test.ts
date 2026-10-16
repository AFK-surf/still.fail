// The Rust core's looks.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { answer, face, glyph, linkShown, listNote, memorySections, stationLine, stationUpdate } from "../src/looks.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const station = (address: string, name: string, state: string) => ({ station: address, id: address, name, state, message: null });

test("the_glyph_counts_stations_by_their_links_and_says_who_works", () => {
  const stations = [station("w/a", "Studio", "online"), station("w/b", "MBA", "online"), station("w/c", "Pi", "offline"), station("w/d", "X", "error")];
  const days = [{ items: [{ station: "w/a", state: "run" }, { station: "w/c", state: "run" }, { station: "w/b", state: null }] }];
  let g = glyph(stations, days);
  assert.deepEqual([g.online, g.dim, g.failing, g.working], [2, 1, 1, 1]);
  assert.equal(g.summary, "4 台 station · 1 台运行中");
  assert.equal(g.label, "4 台 station，2 台在线，1 台在干活，1 台离线，1 台出错");
  assert.equal(glyph([station("w/a", "Studio", "online")], days).summary, "Studio · 运行中");
  assert.equal(glyph([], []).label, "0 台 station，0 台在线");
  g = glyph([station("w/a", "A", "connecting"), station("w/b", "B", "offline")], []);
  assert.deepEqual([g.dim, g.connecting], [2, 1]);
  assert.equal(g.label, "2 台 station，0 台在线，1 台正在连接，1 台离线");
});

test("a_list_with_no_rows_says_it_reads_fails_or_has_none", () => {
  const days = [{ items: [{}] }];
  assert.deepEqual(listNote([station("w/a", "A", "error")], days, false, []), { reading: false, failing: [], empty: false });
  assert.equal(listNote([station("w/a", "A", "connecting")], [], false, []).text, "正在连接 A");
  assert.equal(listNote([station("w/a", "A", "connecting"), station("w/b", "B", "connecting")], [], false, []).text, "正在连接 2 台 station");
  assert.equal(listNote([station("w/a", "A", "online")], [], true, []).text, "正在读取会话");
  assert.equal(listNote([station("w/a", "A", "online")], [], true, []).reading, true);
  assert.equal(listNote([station("w/a", "A", "connecting")], [], false, []).reading, true);
  const failing = listNote([station("w/a", "A", "error"), station("w/b", "B", "online")], [], false, []);
  assert.equal(failing.failing[0].text, "无法连接「A」，正在重试…");
  assert.equal(failing.empty, false);
  assert.equal(listNote([station("w/b", "B", "online")], [], false, []).empty, true);
  assert.equal(listNote([], [], false, []).empty, true);
  const unread = listNote([station("w/a", "A", "offline")], [], false, ["w/a"]);
  assert.deepEqual([unread.empty, unread.failing[0].text], [false, "A 离线 · 尚未读取会话"]);
  assert.equal(listNote([station("w/a", "A", "offline")], [], false, []).empty, true);
});

test("a_skill_reads_without_its_frontmatter", () => {
  const memory: J = {
    global: { path: "g", text: "x" },
    skills: [
      { name: "a", description: "项目记忆：做 a 时", project: true, text: "---\nname: a\n---\n\n# A\n" },
      { name: "b", description: "别的", project: false, text: "no front" },
    ],
  };
  answer("GET", "/memory", memory);
  assert.deepEqual([memory.skills[0].body, memory.skills[0].about], ["# A", "做 a 时"]);
  assert.deepEqual([memory.skills[1].body, memory.skills[1].about], ["no front", "别的"]);
});

test("the_memory_reads_in_parts_with_how_long_each_is", () => {
  const memory: J = {
    global: { path: "g", text: "# ember memory\n\n## 回复\n- 一\n- 二\n\n```\n## 不是标题\n- 也不是一条\n```\n## 机器\n本机不编译\n" },
    skills: [{
      name: "ember", description: "项目记忆：ember / still.fail（团队聊天里的 agent）。开发 ember 时使用。", project: true, text: "---\nname: ember\n---\n总览",
      files: [{ name: "design.md", text: "设计" }],
    }],
  };
  answer("GET", "/memory", memory);
  assert.deepEqual(memory.global.sections.map((s: J) => [s.title, s.note]), [["回复", "2 条"], ["机器", "15 B"]]);
  assert.match(memory.global.sections[0].text, /## 不是标题/);
  const skill = memory.skills[0];
  assert.equal(skill.brief, "ember / still.fail。开发 ember 时使用。");
  assert.deepEqual([skill.files[0].label, skill.files[0].size, skill.size], ["design", "6 B", "12 B"]);
  assert.deepEqual(memorySections("开头的话\n## 一\n- a").map((s: J) => s.title), ["开头", "一"]);
  assert.deepEqual(memorySections("# 标题\n只有一段").map((s: J) => [s.title, s.text]), [["全文", "只有一段"]]);
  assert.deepEqual(memorySections(""), []);
});

test("a_chat_link_is_said_only_while_down_or_coming_back", () => {
  assert.deepEqual(linkShown({ state: "error", message: "无法连接此 station：超时" }, "Studio"), { tone: "trouble", text: "无法连接「Studio」", detail: "超时" });
  assert.equal(linkShown({ state: "offline", message: "别的：原因" }, "").detail, "别的：原因");
  assert.equal(linkShown({ state: "offline" }, "").text, "无法连接 station");
  assert.deepEqual(linkShown({ state: "reconnecting" }, "S"), { tone: "busy", text: "正在重连「S」" });
  assert.equal(linkShown({ state: "online" }, "S"), null);
  assert.equal(face(true, { counts: { running: 2 } }), "working");
  assert.equal(face(false, { counts: { running: 2 } }), "offline");
  assert.equal(stationLine(true, { cpuModel: "" }), "在线");
});

test("update_progress_and_pending_messages_survive_disconnect_and_clear_on_new_overview", () => {
  const overview: J = { updates: [{ id: "station", state: "updating", progress: "正在下载新版本…" }] };
  const chat: J = { link: { state: "online" }, outbox: [] };
  assert.equal(stationUpdate(overview, chat, null, false, true).detail, "正在下载新版本…");
  chat.link.state = "reconnecting";
  chat.outbox = [{ id: "one", state: "sending" }];
  const notice = stationUpdate(overview, chat, null, false, true, "Mac Studio");
  assert.equal(notice.text, "「Mac Studio」正在更新");
  assert.equal(notice.station, "Mac Studio");
  assert.ok(notice.detail.includes("消息仍在发送"));
  chat.outbox[0].state = "failed";
  assert.ok(!stationUpdate(overview, chat, null, false, true).detail.includes("消息仍在发送"));
  chat.outbox[0].state = "sending";
  chat.outbox[0].seq = 7;
  assert.ok(!stationUpdate(overview, chat, null, false, true).detail.includes("消息仍在发送"));
  overview.updates[0] = { id: "station", state: "idle", newer: false };
  assert.equal(stationUpdate(overview, chat, null, false, true), null);
  assert.equal(stationUpdate(undefined, chat, null, false, true), null);
});

test("dismissal_is_version_and_channel_scoped_and_never_hides_progress", () => {
  const overview: J = { updates: [{ id: "station", state: "idle", newer: true, updatable: true, latest: "2", channel: "stable" }] };
  assert.equal(stationUpdate(overview, null, "stable:2", false, true), null);
  const next = stationUpdate(overview, null, "stable:1", true, false);
  assert.equal(next.open, true);
  assert.equal(next.canUpdate, false);
  assert.equal(next.dismissible, true);
  assert.notEqual(stationUpdate(overview, null, "beta:2", false, true), null);
  overview.updates[0].state = "updating";
  const progress = stationUpdate(overview, null, "stable:2", false, true);
  assert.equal(progress.label, "更新中");
  assert.equal(progress.dismissible, false);
});

test("update_says_which_station_and_versions", () => {
  const overview: J = { updates: [{ id: "station", state: "updating", version: "0.1.10", latest: "0.1.12", percent: 140, progress: "正在下载新版本…" }] };
  const chat: J = { link: { state: "online" }, outbox: [] };
  const notice = stationUpdate(overview, chat, null, false, true, "studio");
  assert.equal(notice.station, "studio");
  assert.equal(notice.from, "0.1.10");
  assert.equal(notice.to, "0.1.12");
  assert.equal(notice.percent, 100);
  chat.link.state = "reconnecting";
  assert.equal(stationUpdate(overview, chat, null, false, true, "studio").percent, null);
  overview.updates[0].latest = "0.1.10";
  assert.equal(stationUpdate(overview, null, null, false, true).to, null);
  assert.equal(stationUpdate(overview, null, null, false, true).station, "station");
});

test("availability_explains_deferral_only_when_automatic_updates_are_enabled", () => {
  const overview: J = { updates: [{ id: "station", state: "idle", newer: true, updatable: true, auto: true, idleOnly: true }] };
  assert.ok(stationUpdate(overview, null, null, false, true).detail.includes("空闲时自动更新"));
  overview.updates[0].auto = false;
  assert.equal(stationUpdate(overview, null, null, false, true).detail, "可立即更新");
});
