// entries.rs, activity.rs, brand.rs and doing.rs's tests, ported (same names, same checks).
import assert from "node:assert/strict";
import { test } from "node:test";
import { doing, epochMs, tasksOf, told } from "../src/activity.ts";
import { activity as present } from "../src/history.ts";
import { name, setOwnApp, setTestChannel, STABLE, TEST, testApp } from "../src/brand.ts";
import { Core } from "../src/core.ts";
import { Doing } from "../src/doing.ts";
import { conformTy } from "../src/conform.ts";
import { merge } from "../src/entries.ts";
import { badgeOf, Counts, lastChat, rowTone } from "../src/views/marks.ts";
import { barsOf, shown } from "../src/prefs.ts";
import { FakeHost } from "../src/testing.ts";
import "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const message = (n: number, text: string): J => ({ thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "person", author: "a@x.com", authorName: "阿", text, attachments: [], quotes: [], declared: null, at: n * 10 });
const change = (n: number, kind: string, target: number, text: string | null): J => ({ thread: 7, n, kind, target, ts: null, authorKind: "person", author: "a@x.com", authorName: "阿", text, attachments: [{ name: "b.png" }], quotes: [], declared: null, at: n * 10 });

test("edits_merge_into_their_messages", () => {
  const first = { ...message(1, "一"), agentIdentity: { model: "gpt-6-sol" } };
  const entries = [first, message(2, "二"), change(3, "edit", 1, "一（改）"), message(4, "三"), change(5, "edit", 1, "一（再改）"), message(6, "四")];
  const merged = merge(entries) as J[];
  assert.deepEqual(merged.map((m) => [m.seq, m.text]), [[1, "一（再改）"], [2, "二"], [4, "三"], [6, "四"]]);
  assert.equal(merged[0].agentIdentity.model, "gpt-6-sol");
  assert.equal(merged[0].editedAt, 50);
  assert.equal(merged[0].createdAt, 10);
  assert.deepEqual(merged[0].attachments, [{ name: "b.png" }], "an edit gives the message's whole new version");
  assert.equal(merged[1].editedAt, null);
  assert.equal(merged[1].authorName, "阿");
  // Changes to messages before the run have nothing to change.
  assert.deepEqual((merge(entries.slice(2)) as J[]).map((m) => m.seq), [4, 6]);
});

test("a_block_post_keeps_its_options", () => {
  const asked = { ...message(1, "选哪个？"), options: [{ label: "A" }] };
  const merged = merge([asked, message(2, "A")]) as J[];
  assert.deepEqual([merged[0].options, merged[1].options], [[{ label: "A" }], undefined]);
  const typed = { ...message(1, "key？"), card: { type: "text" } };
  assert.deepEqual((merge([typed]) as J[])[0].card, { type: "text" });
});

test("a_card_restated_by_an_edit_replaces_the_posts_unedited", () => {
  const asked = { ...message(1, "申请使用「GitHub」"), card: { type: "options", vault: { request: "r_1" } } };
  const restated = { ...change(2, "edit", 1, "申请使用「GitHub」"), attachments: [], card: { type: "options", vault: { request: "r_1", outcome: { status: "denied" } } } };
  const [m] = merge([asked, restated]) as J[];
  assert.deepEqual(m.card.vault.outcome, { status: "denied" });
  assert.equal(m.editedAt, null, "the same words: not an edit of them");
});

test("a_notice_about_a_profile_says_which", () => {
  const notice = { ...message(1, "⚠️ 认证失败"), authorKind: "ember", profile: "cc" };
  const merged = merge([notice, message(2, "二")]) as J[];
  assert.deepEqual([merged[0].profile, merged[1].profile], ["cc", undefined]);
});

const now = (live: J): [string, string] => {
  const a = present(live) as J;
  return [a.now.key, a.now.text];
};

test("it_says_the_call_it_runs_or_its_reply_or_where_the_turn_stands", () => {
  // The call its execution history shows running (this turn's, with no result yet), said as the history says it: the
  // same call keeps its key. A step's own copy of a call's input is not read.
  const timeline = [
    { kind: "tool_call", tool: "Bash", text: '{"command":"old"}', callId: "s9" },
    { kind: "user", text: "next" },
    { kind: "tool_call", tool: "Read", text: '{"file_path":"/w/a.ts"}', callId: "s0" },
    { kind: "tool_result", callId: "s0", ok: true, text: "x" },
    { kind: "thinking", text: "plan" },
    { kind: "tool_call", tool: "Bash", text: '{"command":"cargo test --workspace","description":"Run the tests"}', callId: "s2" },
    { kind: "tool_call", tool: "Grep", text: '{"pattern":"TODO"}', callId: "s3", subagent: true },
  ];
  const steps = [{ id: "s2", step: "tool", tool: "Bash", input: '{"command":"other"}' }];
  assert.equal(present({ timeline, steps }).now.mono, true);
  assert.equal(present({ timeline: timeline.slice(0, 5), phase: { phase: "thinking" } }).now.mono, undefined);
  assert.deepEqual(now({ timeline, steps, phase: { phase: "working" } }), ["s2", "Run the tests"]);
  assert.deepEqual(now({ timeline: timeline.slice(0, 5), phase: { phase: "thinking" } }), ["think", "思考中"], "nothing of this turn runs");
  // Writing its reply (chat_post's input streaming in); chat_state says nothing of its own.
  assert.deepEqual(now({ steps: [{ id: "p", step: "tool", tool: "mcp__ember__chat_post", input: '{"to' }] }), ["reply", "正在回复"]);
  assert.deepEqual(now({ steps: [{ id: "p", step: "tool", tool: "mcp__stillfail__chat_post", input: '{"to' }] }), ["reply", "正在回复"]);
  assert.deepEqual(now({ steps: [{ id: "t", step: "thinking" }], rate: 30 }), ["think", "思考中 · ≈ 30 token/s"]);
  // Where the turn stands; the rate changes the words, not the thing.
  assert.deepEqual(now({ phase: { phase: "requesting" } }), ["requesting", "请求中"]);
  assert.deepEqual(now({ phase: { phase: "responding" }, rate: 42 }), ["write", "输出中 · ≈ 42 token/s"]);
  assert.deepEqual(now({ phase: { phase: "thinking" } }), ["think", "思考中"]);
  assert.deepEqual(now({ phase: { phase: "starting" } }), ["starting", "正在启动"]);
  assert.deepEqual(now({}), ["busy", "处理中"]);
  // Writing its reply, at its rate.
  assert.deepEqual(now({ steps: [{ id: "p", step: "tool", tool: "mcp__ember__chat_post", input: '{"to' }], rate: 55 }), ["reply", "正在回复 · ≈ 55 token/s"]);
  // A call not in its transcript yet changes nothing: what the turn was doing still shows, until the history has it.
  assert.deepEqual(now({ steps: [{ id: "b", step: "tool", tool: "Bash", input: '{"command":"ls"}' }], phase: { phase: "thinking" } }), ["think", "思考中"]);
  // A call's own description says it best.
  assert.equal(doing("Bash", '{"command":"npm i","description":"安装依赖"}'), "安装依赖");
  assert.equal(doing("Read", '{"file_path":"/w/web/src/Chat.tsx"}'), "读取 Chat.tsx");
  // DeepSeek Harness's lowercase names are said as Claude Code's are.
  assert.equal(doing("read", '{"file_path":"/w/web/src/Chat.tsx"}'), "读取 Chat.tsx");
  assert.equal(doing("bash", '{"command":"ls -la"}'), "运行 ls -la");
  assert.equal(doing("grep", '{"pattern":"TODO"}'), "搜索 TODO");
  assert.equal(doing("web_search", '{"queries":["deepseek","harness"]}'), "访问 deepseek harness");
  assert.equal(doing("subagent", '{"prompt":"look around"}'), "分派子 agent look around");
  // An older station's step carries the input's first 300 characters, cut anywhere: what is there is read.
  assert.equal(doing("Bash", '{"command":"node --test","description":"Run account-proxy tests 3 times with new m'), "Run account-proxy tests 3 times with new m…");
  assert.equal(doing("Bash", '{"command":"cd x && ls\\necho'), "运行 cd x && ls");
  // A task on another station is said with where it runs, by the station's name; a task started by its key says what
  // its prepare (earlier in the transcript) runs: its name, else its command's first line that does something.
  const studio = "d2e33e62a1f88dd30e759c734b6604599a6e4024dbb926b1cd81b99c42da4956";
  const stations = new Map([[studio, "Studio"]]);
  const prepare = JSON.stringify({ station: studio, action: "prepare", key: "check", command: "exec 2>&1\nset -e\npnpm test" });
  const tasks = tasksOf([{ kind: "tool_call", tool: "mcp__stillfail__station_task", text: prepare }]);
  assert.equal(doing("mcp__stillfail__station_task", prepare, { stations }), "在 Studio 上准备 pnpm test");
  assert.equal(doing("mcp__stillfail__station_task", JSON.stringify({ station: studio, action: "start", key: "check" }), { stations, tasks }), "在 Studio 上运行 pnpm test");
  assert.equal(doing("mcp__stillfail__station_task", JSON.stringify({ station: studio, action: "log", key: "check" }), { stations, tasks }), "读取 Studio 上 pnpm test 的输出");
  assert.equal(doing("mcp__stillfail__station_task", JSON.stringify({ station: studio, action: "get", key: "lint" }), { stations }), "查看 Studio 上的 lint");
  assert.equal(doing("mcp__stillfail__station_task", JSON.stringify({ station: studio, action: "list" })), "列出 另一台 station 上的任务");
  assert.equal(doing("mcp__stillfail__station_file", JSON.stringify({ station: studio, key: "k", direction: "download", path: "out/shot.png", local: "/w/shot.png" }), { stations }), "从 Studio 下载 shot.png");
  assert.equal(doing("ToolSearch", '{"query":"select:mcp__stillfail__secret_list,mcp__stillfail__station_task","max_results":2}'), "加载工具 secret_list、station_task");
  assert.equal(told("ToolSearch", '{"query":"notebook jupyter"}'), null);
  assert.equal(epochMs("1970-01-02T00:00:01.500Z"), 86_401_500);
});

test("the_name_is_the_channels", () => {
  assert.equal(name(), "still.fail");
  setTestChannel(true);
  assert.equal(name(), "youdid.wtf");
  setTestChannel(false);
  assert.equal(name(), "still.fail");
});

test("an_app_of_its_own_on_the_test_channel_calls_it_still_fail", () => {
  setTestChannel(true);
  setOwnApp(false);
  assert.deepEqual([name(), testApp()], ["still.fail", false]);
  setOwnApp(true);
  assert.deepEqual([name(), testApp()], ["youdid.wtf", true]);
  setTestChannel(false);
});

test("a_core_takes_its_channel_from_its_host", async () => {
  for (const [beta, webOnTest, expected] of [[false, false, STABLE], [true, false, TEST], [false, true, TEST]] as const) {
    const host = new FakeHost();
    host.isBeta = beta;
    host.onTestChannel = webOnTest;
    const core = await Core.create(host, { clock: host.time.clock });
    assert.equal(name(), expected, `beta ${beta}, web on the test channel ${webOnTest}`);
    core.close();
  }
  setTestChannel(false);
});

test("keeps_what_is_under_way_with_its_plain_params", () => {
  const doing = new Doing();
  const a = doing.start("job.stop", { station: "w/s", id: "j1", input: { x: 1 } }, 1000.5);
  const b = doing.start("chat.pin", { station: "w/s", session: "k", pinned: true, thread: 7 }, 2000);
  assert.deepEqual(doing.value(() => false), {
    doing: [
      { call: "job.stop", params: { station: "w/s", id: "j1" }, since: 1000, stage: "running" },
      { call: "chat.pin", params: { station: "w/s", session: "k", pinned: "true", thread: "7" }, since: 2000, stage: "running" },
    ],
  });
  doing.fail(a, "无法连接此 station：无响应");
  assert.deepEqual((doing.value(() => false) as J).doing[0], { call: "job.stop", params: { station: "w/s", id: "j1" }, since: 1000, stage: "failed", error: "无法连接此 station：无响应" });
  doing.end(a);
  doing.end(b);
  assert.deepEqual(doing.value(() => false), { doing: [] });
});

// views/marks.rs
const agentIn = (status: string): J => (status === "running" ? { key: "k", process: "running" } : status === "blocked" ? { key: "k", lastTurn: { declared: "block" } } : { key: "k" });

test("only_a_row_its_person_takes_part_in_wants_them", () => {
  const me = { id: "me@x.com", email: "me@x.com" };
  const failed = { key: "k", lastTurn: { outcome: "failed" } };
  // Waiting is counted by whom it waits for (decisions.forViewer), not by the agent's state.
  assert.equal(rowTone({ mine: true, agents: [agentIn("blocked")] }), null);
  assert.equal(rowTone({ mine: true, unread: true, agents: [agentIn("blocked")] }), null);
  assert.equal(rowTone({ mine: true, agents: [failed] }), "alert");
  assert.equal(rowTone({ mine: true, agents: [failed], creator: { email: "ME@x.com" } }, me), "alert");
  assert.equal(rowTone({ mine: true, agents: [failed], creator: { email: "other@x.com" } }, me), null, "someone else's chat went wrong: theirs");
  assert.equal(rowTone({ mine: false, agents: [failed] }), null);
  assert.equal(rowTone({ mine: true, unread: true, agents: [] }), "done");
  assert.equal(rowTone({ mine: false, unread: true, agents: [] }), null);
  assert.equal(rowTone({ mine: true, unread: true, agents: [agentIn("running")] }), null);
  assert.equal(rowTone({ mine: true, agents: [] }), null);
});

test("the_badge_counts_as_the_prefs_say", () => {
  const c = new Counts(1, 2, 4);
  assert.equal(badgeOf({}, c), 3);
  assert.equal(badgeOf(null, c), 3);
  assert.equal(badgeOf({ badge: "decisions" }, c), 2);
  assert.equal(badgeOf({ badge: "all" }, c), 7);
  // Kind by kind (the notifications page): what is not said as `badge` says; someone else's unread apart (1 of the 4).
  assert.equal(badgeOf({ badgeKinds: { wait: true, failed: false, done: false, message: false } }, c, 1), 2);
  assert.equal(badgeOf({ badgeKinds: { message: true } }, c, 1), 4, "the cards, what went wrong, someone else's unread");
  assert.equal(badgeOf({ badge: "all", badgeKinds: { message: false } }, c, 1), 6, "all but someone else's unread");
  assert.equal(badgeOf({ badge: "all", badgeKinds: { on: false } }, c, 1), 0, "no badge at all");
});

test("a_phones_bottom_bars_read_whole_from_what_is_kept", () => {
  const two = { sets: [["chats", "files", "profiles", "stations"], ["usage", "connects", "archive"]], current: 0 };
  assert.deepEqual(barsOf(undefined), two, "nothing kept: the two default bars");
  assert.deepEqual(barsOf({ sets: [], current: 0 }), two, "no bar left: the default");
  assert.deepEqual(barsOf({ sets: [["files", "nope", "files", "chats", "usage", "archive", "stations"]], current: 3 }), { sets: [["files", "chats", "usage", "archive"]] , current: 0 },
    "unknown places and repeats left out, four at most, the bar in view one there is");
  assert.deepEqual(barsOf({ sets: [["x"], ["files"]], current: 1 }), { sets: [["files"]], current: 0 }, "a bar with nothing known goes");
  assert.deepEqual(barsOf({ sets: [["chats", "decisions"], ["decisions"]], current: 1 }), { sets: [["chats"]], current: 0 }, "奏, kept by an older build, is gone");
  assert.deepEqual(barsOf({ sets: [["chats"], ["files"]], current: 1 }), { sets: [["chats"], ["files"]], current: 1 });
});
test("each_workspaces_bottom_bars_go_out_whole", () => {
  const out = shown({ barsBy: { a: { sets: [["files", "nope"]], current: 4 }, b: "junk" } }) as { barsBy: Record<string, unknown> };
  assert.deepEqual(out.barsBy.a, { sets: [["files"]], current: 0 }, "a workspace's bars read as `bars` do");
  assert.deepEqual(out.barsBy.b, barsOf(undefined), "one unreadable: the default");
  assert.deepEqual((shown({}) as { barsBy: unknown }).barsBy, {}, "none kept: no workspace's");
  // 奏 as a workspace's list, kept by an older build: that workspace goes by the one-for-all fields again.
  assert.deepEqual((shown({ listFilter: { a: "decisions", b: "mine" } }) as { listFilter: unknown }).listFilter, { b: "mine" });
});


test("the_chat_last_open_is_the_cores_else_the_path_a_page_kept", () => {
  const kept = { openChat: { ws: { station: "ws/a", key: "k1" } }, lastChat: { ws: "/w/ws/s/b/chats/k2" } };
  assert.deepEqual(lastChat(kept, "ws"), { station: "ws/a", key: "k1" });
  const old = { lastChat: { ws: "/w/ws/s/b/chats/thread%3A7", x: "/w/x/new", y: "/w/y/s/c/chats/new%3A1" } };
  assert.deepEqual(lastChat(old, "ws"), { station: "ws/b", key: "thread:7" });
  assert.equal(lastChat(old, "x"), null);
  assert.equal(lastChat(old, "y"), null);
  assert.equal(lastChat(old, "z"), null);
});

test("marks_say_how_many_and_how_urgent", () => {
  const counts = (alert: number, wait: number, unread: number) => new Counts(alert, wait, unread);
  assert.equal(counts(1, 1, 3).tone(), "alert");
  assert.equal(counts(0, 1, 3).tone(), "wait");
  assert.equal(counts(0, 0, 3).tone(), "done");
  assert.equal(counts(0, 0, 0).tone(), null);
  assert.equal(counts(2, 0, 3).label(), "2 个出错 · 3 个有新消息");
  assert.equal(counts(0, 1, 1).label(), "1 个待你处理 · 1 个有新消息");
  assert.equal(counts(0, 0, 1).label(), "1 个有新消息");
});

test("marks_are_said_in_english_too", () => {
  const counts = (alert: number, wait: number, unread: number) => new Counts(alert, wait, unread);
  assert.equal(counts(2, 1, 1).labelIn("en"), "2 failed · 1 waiting for you · 1 unread");
  assert.equal(counts(1, 0, 3).labelIn("en"), "1 failed · 3 unread");
  assert.equal(counts(0, 0, 1).labelIn("zh"), "1 个有新消息");
});

// The shapes (src/shapes/schema.ts): a union's words are serde's camelCase of its variants (the TS core's first table,
// read from the Rust source, had them capitalized, and a history item would not have gone out).
test("a_history_item_goes_out_through_its_shape", () => {
  const item = { key: "k", entries: [1, 2], body: { kind: "mark", content: { text: "等 CI", wait: { since: 5 } } } };
  assert.deepEqual(conformTy("HistoryItem", item), { ok: item });
  assert.match((conformTy("HistoryBody", { kind: "Mark", content: { text: "x" } }) as J).error, /unknown variant `Mark`/);
});
