// entries.rs, activity.rs, brand.rs and doing.rs's tests, ported (same names, same checks).
import assert from "node:assert/strict";
import { test } from "node:test";
import { callText, epochMs, present } from "../src/activity.ts";
import { name, setTestChannel, STABLE, TEST } from "../src/brand.ts";
import { Core } from "../src/core.ts";
import { Doing } from "../src/doing.ts";
import { conformTy } from "../src/conform.ts";
import { merge } from "../src/entries.ts";
import { badgeOf, Counts, lastChat, rowTone } from "../src/views/marks.ts";
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
  // The newest call it runs, by its step: the same call keeps its key.
  const steps = [
    { id: "s0", step: "tool", tool: "Read", input: '{"file_path":"/w/a.ts"}', ended: true },
    { id: "s1", step: "thinking" },
    { id: "s2", step: "tool", tool: "Bash", input: '{"command":"cargo test --workspace","descr' },
    { id: "s3", step: "tool", tool: "Grep", input: '{"pattern":"TODO"}', subagent: true },
  ];
  assert.deepEqual(now({ steps, phase: { phase: "working" } }), ["s2", "运行 cargo test --workspace"]);
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
  // A call whose input has not come yet changes nothing: what the turn was doing still shows, until it says what it runs.
  assert.deepEqual(now({ steps: [{ id: "b", step: "tool", tool: "Bash", input: "" }], phase: { phase: "thinking" } }), ["think", "思考中"]);
  assert.deepEqual(now({ steps: [{ id: "b", step: "tool", tool: "Bash", input: '{"command":"ls"}' }] }), ["b", "运行 ls"]);
  // A call's own description says it best.
  assert.equal(callText("Bash", '{"command":"npm i","description":"安装依赖"}'), "安装依赖");
  assert.equal(epochMs("1970-01-02T00:00:01.500Z"), 86_401_500);
});

test("the_name_is_the_channels", () => {
  assert.equal(name(), "still.fail");
  setTestChannel(true);
  assert.equal(name(), "youdid.wtf");
  setTestChannel(false);
  assert.equal(name(), "still.fail");
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
  doing.fail(a, "连不上这台 station：没有回应");
  assert.deepEqual((doing.value(() => false) as J).doing[0], { call: "job.stop", params: { station: "w/s", id: "j1" }, since: 1000, stage: "failed", error: "连不上这台 station：没有回应" });
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
  assert.equal(counts(2, 0, 3).label(), "2 个出错了 · 3 个有新消息");
  assert.equal(counts(0, 1, 1).label(), "1 个在等你 · 1 个有新消息");
  assert.equal(counts(0, 0, 1).label(), "1 个有新消息");
});

test("marks_are_said_in_english_too", () => {
  const counts = (alert: number, wait: number, unread: number) => new Counts(alert, wait, unread);
  assert.equal(counts(2, 1, 1).labelIn("en"), "2 went wrong · 1 waiting for you · 1 unread");
  assert.equal(counts(1, 0, 3).labelIn("en"), "1 went wrong · 3 unread");
  assert.equal(counts(0, 0, 1).labelIn("zh"), "1 个有新消息");
});

// The shapes (src/shapes/schema.ts): a union's words are serde's camelCase of its variants (the TS core's first table,
// read from the Rust source, had them capitalized, and a history item would not have gone out).
test("a_history_item_goes_out_through_its_shape", () => {
  const item = { key: "k", entries: [1, 2], body: { kind: "mark", content: { text: "等 CI", wait: { since: 5 } } } };
  assert.deepEqual(conformTy("HistoryItem", item), { ok: item });
  assert.match((conformTy("HistoryBody", { kind: "Mark", content: { text: "x" } }) as J).error, /unknown variant `Mark`/);
});
