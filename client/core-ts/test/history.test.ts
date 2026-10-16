// The Rust core's history.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import * as format from "../src/format.ts";
import { args, doing } from "../src/activity.ts";
import { hint, parsePrompt, parseTasks, presentHistory, type Context } from "../src/history.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

test("reads_a_call_cut_short", () => {
  const cut = '{\n  "file_path": "/a/b.ts",\n  "content": "line one\\nline t\n… (1200 more characters)';
  assert.equal(hint(cut), "/a/b.ts");
  assert.equal(args(cut)!.content, "line one\nline t…");
  assert.deepEqual(args('{"a": [1, 2,\n… (9 more characters)')!.a, [1, 2]);
});

const cx = (threads: J[], members: J[], slack: string[]): Context => ({
  threads,
  members,
  slackUsers: slack,
  botUserId: "UBOT",
  botName: "ds-ember",
  runtime: "codex",
  started: true,
  offsetMin: 480,
  workspaces: new Map([["T1", { name: "Acme", url: "https://acme.slack.com/" }]]),
});

test("a_slack_place_is_named_with_its_workspace_and_links_to_its_thread", () => {
  const threads = [{ surface: "slack:T1", channel: "C1", threadTs: "1.000200", channelName: "ops", sessions: [{ session: "s1" }] }];
  const c = cx(threads, [], []);
  const place = format.place(c.threads, "C1/1.000200", c.offsetMin, c.workspaces) as J;
  assert.deepEqual([place.name, place.url], ["Acme#ops", "https://acme.slack.com/archives/C1/p1000200"]);
  const unknown = format.place(c.threads, "C9/2.0", c.offsetMin, c.workspaces) as J;
  assert.deepEqual([unknown.name, unknown.url], ["#C9", null]);
});

test("a_prompt_is_the_messages_it_carried_and_embers_words_around_them", () => {
  const [said] = parsePrompt('<message via="slack" connect="cl" you="ember (<@UBOT>)" thread="C1/1.0" from="Ada (U1)" ts="1.2">\nhi\n</message>');
  assert.deepEqual([said.length, said[0].user, said[0].ts, said[0].text], [1, "U1", "1.2", "hi"]);
  const [messages, note] = parsePrompt('Heads up.\n<message via="slack" from="Ada &amp; Co (U1)" ts="1.2" thread="C1/1.0">\nhi <@UBOT>\n</message>\n(Thread C1/1.0 had messages before you were brought in; read them.)');
  assert.equal(note, "Heads up.");
  assert.deepEqual(messages, [{ user: "U1", name: "Ada & Co", ts: "1.2", text: "hi <@UBOT>", thread: "C1/1.0", slack: true }]);
  const [old] = parsePrompt('<slack user="U2" bot ts="3.4">\nyo\n</slack>');
  assert.equal(old[0].user, "U2");
  assert.equal(old[0].text, "yo");
});

test("a_task_notification_is_read_into_how_the_work_ended", () => {
  const note = (status: string, summary: string, more = "") =>
    `<task-notification>\n<task-id>b1</task-id>\n<tool-use-id>toolu_1</tool-use-id>\n<output-file>/tmp/b1.output</output-file>\n<status>${status}</status>\n<summary>${summary}</summary>${more}\n</task-notification>`;
  const [tasks, rest] = parseTasks(
    `Heads up.\n${note("completed", 'Background command "Push and wait for "CI"" completed (exit code 0)')}\n` +
      note("failed", 'Background command "Run tests" failed with exit code 2') +
      note("killed", 'Background command "Watch" was stopped after reaching its background time limit', "\n<note>more</note>") +
      note("completed", 'Agent "Map it" finished', "\n<note>n</note>\n<result>## Found\n**it**</result>\n<usage>u</usage>"),
  );
  assert.equal(rest, "Heads up.");
  assert.deepEqual(tasks, [
    { agent: false, name: 'Push and wait for "CI"', status: "completed", code: 0, result: null },
    { agent: false, name: "Run tests", status: "failed", code: 2, result: null },
    { agent: false, name: "Watch", status: "killed", code: null, result: null },
    { agent: true, name: "Map it", status: "completed", code: null, result: "## Found\n**it**" },
  ]);
  const h = presentHistory({ loaded: true, timeline: [{ kind: "user", text: note("failed", 'Background command "Run tests" failed with exit code 2') }] }, cx([], [], []));
  const received = h.items[0].body.content;
  assert.equal(received.note, null);
  assert.deepEqual(received.tasks, [{ text: "后台命令失败（退出码 2）：Run tests", agent: false, failed: true, result: null, md: null }]);
});

test("boundaries_stand_alone_and_the_work_between_folds_into_a_group", () => {
  const threads = [{ channel: "C1", threadTs: "1.0", channelName: "ops", sessions: [{ session: "s1" }] }];
  const members = [{ email: "a@x.com", name: "阿一" }];
  const slack = ["U1"];
  const live = {
    loaded: true,
    timeline: [
      { kind: "user", text: '<message via="slack" from="Ada (U1)" ts="1.2" thread="C1/1.0">\nhi <@UBOT>\n</message>' },
      { kind: "thinking", text: "\nplan it\nmore" },
      { kind: "tool_call", tool: "Read", text: '{"file_path":"/a.ts"}', callId: "a", at: "2026-09-27T00:00:00.000Z" },
      { kind: "tool_result", callId: "a", ok: true, text: "x", at: "2026-09-27T00:00:02.000Z" },
      { kind: "tool_call", tool: "Read", text: '{"file_path":"/a.ts"}', callId: "b" },
      { kind: "tool_call", tool: "Bash", text: '{"command":"ls","description":"看看目录"}', callId: "c" },
      { kind: "tool_result", callId: "c", ok: false, text: "no" },
      { kind: "tool_call", tool: "mcp__ember__chat_post", text: '{"to":"C1/1.0","text":"done","kind":"block"}', callId: "d" },
      { kind: "tool_call", tool: "mcp__ember__chat_state", text: '{"kind":"final"}' },
      { kind: "assistant", text: "ok" },
    ],
    steps: [{ id: "s", step: "thinking" }, { id: "t", step: "tool", tool: "Bash" }],
    phase: { phase: "starting", since: 5 },
    usage: { modelCalls: 3, inputTokens: 2000, cachedTokens: 1000, outputTokens: 50 },
  };
  const h = presentHistory(live, cx(threads, members, slack));
  const items = h.items;
  assert.deepEqual(items.map((i: J) => i.body.kind), ["received", "group", "post", "mark", "text"]);
  const m = items[0].body.content.messages[0];
  assert.deepEqual([m.from.name, m.text, m.place.name, m.place.session], ["你", "hi @ds-ember", "#ops", "s1"]);
  const g = items[1].body.content;
  assert.equal(g.summary, "看看目录 · 共 3 项");
  // Named by its latest call as the chat's activity says that call while it runs.
  assert.equal(presentHistory({ ...live, timeline: live.timeline.slice(0, 5) }, cx(threads, members, slack)).items[1].body.content.summary, `${doing("Read", '{"file_path":"/a.ts"}')} · 共 2 项`);
  assert.equal(g.title, "读取 1 个文件、运行 1 条命令");
  assert.deepEqual([g.failures, g.pending], [1, 1]);
  assert.deepEqual(g.rows.map((r: J) => r.kind), ["thought", "step", "step", "step"]);
  assert.equal(g.rows[0].content.first, "plan it");
  assert.equal(g.rows[1].content.meta, "2 秒");
  assert.equal(g.rows[2].content.meta, "进行中");
  assert.deepEqual(items[1].entries, [1, 6]);
  assert.deepEqual([items[2].body.content.block, items[2].body.content.place.name, items[2].body.content.ends], [true, "#ops", "human"]);
  assert.deepEqual([items[3].body.content.text, items[3].body.content.ends], ["标记为做完了", "done"]);
  assert.deepEqual(items[0].turn, { text: "3 步 · 发出 1 条" });
  const waits = (a: string, next: string | null) => {
    const timeline: J[] = [{ kind: "tool_call", tool: "mcp__ember__chat_state", text: a, at: "2026-09-27T00:00:00.000Z" }];
    if (next !== null) timeline.push({ kind: "user", text: '<message via="ember">done</message>', at: next });
    return presentHistory({ loaded: true, timeline }, cx(threads, members, slack)).items[0].body.content;
  };
  const back = waits('{"kind":"waiting","seconds":150}', "2026-09-27T00:01:20.000Z");
  assert.equal(back.text, "等待了 1m 20s / 2m 30s");
  assert.deepEqual(back.wait, { since: 1790467200000, until: 1790467280000, seconds: 150, what: null });
  assert.equal(waits('{"kind":"waiting","seconds":60}', "2026-09-27T01:00:00.000Z").text, "等待了 1m / 1m");
  const now = waits('{"kind":"waiting","seconds":600}', null);
  assert.deepEqual([now.text, now.wait.until], ["等待中，最长 10m", null]);
  // What it waited for (chat_state's `for`) leads its words, and goes with the wait for the pages' running count.
  const ci = waits('{"kind":"waiting","seconds":600,"for":"CI 跑完"}', "2026-09-27T00:05:00.000Z");
  assert.deepEqual([ci.text, ci.wait.what], ["CI 跑完 · 等待了 5m / 10m", "CI 跑完"]);
  assert.deepEqual(h.live, [{ id: "s", text: "正在思考…" }]);
  assert.equal(h.phase.text, "正在启动 Codex");
  assert.equal(h.usage[4].value, "50%");
  assert.equal(h.usageLine, "调用 3 次 · 输入 2K（缓存 50%） · 输出 50");
  assert.equal(h.edge, "已到 Session 开始处");
  // A station since tells the context and the cost too.
  const more = (usage: J) => presentHistory({ ...live, usage: { ...live.usage, ...usage } }, cx(threads, members, slack));
  const now2 = more({ contextTokens: 86_000, cost: 3.214, unpricedCalls: 0 });
  assert.deepEqual(now2.usage.slice(5), [{ label: "上下文", value: "86K" }, { label: "费用估算", value: "$3.21" }]);
  assert.equal(now2.usageLine, "调用 3 次 · 输入 2K（缓存 50%） · 输出 50 · 上下文 86K · 约 $3.21");
  assert.equal(more({ contextTokens: 86_000, contextWindow: 258_000, cost: 1, unpricedCalls: 1 }).usage[5].value, "86K / 258K（33%）");
  assert.equal(more({ contextTokens: 1, cost: 1, unpricedCalls: 1 }).usage[6].value, "≥$1.00");
  assert.equal(more({ contextTokens: 1, cost: 0, unpricedCalls: 3 }).usage[6].value, "模型没有价目");
});

test("an_empty_history_says_why", () => {
  const edge = (live: J, started: boolean) => presentHistory(live, { ...cx([], [], []), started }).edge;
  assert.equal(edge({ loaded: false }, true), "正在读取执行历史…");
  assert.equal(edge({ loaded: true }, false), "运行时还没开始这个会话。");
  assert.equal(edge({ loaded: true, offline: true }, true), "station 离线，这台设备上还没有这个会话的执行历史。");
});

test("a_timeline_loaded_from_further_on_counts_entries_from_the_transcripts_start", () => {
  const live = {
    loaded: true,
    first: 400,
    timeline: [
      { kind: "user", text: "hi" },
      { kind: "tool_call", tool: "Bash", text: '{"command":"ls"}', callId: "a" },
      { kind: "tool_result", callId: "a", ok: true, text: "x" },
    ],
  };
  const h = presentHistory(live, cx([], [], []));
  assert.deepEqual([h.items[0].key, h.items[1].entries], ["e400", [401, 402]]);
  assert.deepEqual([h.more, h.edge, h.empty], [true, "正在读取更早的执行历史…", false]);
  assert.equal(presentHistory({ loaded: true, first: 400, timeline: [] }, cx([], [], [])).more, true);
});

test("a_groups_thinking_and_calls_keep_the_order_they_came_in", () => {
  const timeline = [
    { kind: "thinking", text: "first" },
    { kind: "tool_call", tool: "Read", text: '{"file_path":"/a.ts"}', callId: "a" },
    { kind: "tool_result", callId: "a", ok: true, text: "x" },
    { kind: "thinking", text: "second" },
    { kind: "tool_call", tool: "Bash", text: '{"command":"ls"}', callId: "b" },
    { kind: "tool_result", callId: "b", ok: true, text: "y" },
    { kind: "thinking", text: "third" },
  ];
  const g = presentHistory({ loaded: true, timeline }, cx([], [], [])).items[0].body.content;
  assert.deepEqual(g.rows.map((r: J) => (r.kind === "thought" ? r.content.text : r.content.name)), ["first", "Read", "second", "Bash", "third"]);
});

test("a_post_read_from_the_transcript_stands_where_it_was_made", () => {
  const timeline = [
    { kind: "thinking", text: "plan" },
    { kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"C1/1.0","text":"done"}', callId: "p" },
    { kind: "tool_result", callId: "p", ok: true, text: "Posted to C1/1.0." },
    { kind: "assistant", text: "after" },
  ];
  const items = presentHistory({ loaded: true, timeline }, cx([], [], [])).items;
  assert.deepEqual(items.map((i: J) => i.body.kind), ["group", "post", "text"]);
  assert.equal(items[1].body.content.text, "done");
});

test("each_prompt_that_woke_the_agent_begins_a_turn_saying_when_and_what_it_did", () => {
  const timeline = [
    { kind: "tool_call", tool: "Bash", text: '{"command":"ls"}', callId: "z" },
    { kind: "user", text: '<message via="web" from="Ada (a@x.com)" ts="1.2" thread="EMBER/1.0">\nhi\n</message>', at: "2026-09-27T01:02:00.000Z" },
    { kind: "tool_call", tool: "Read", text: '{"file_path":"/a.ts"}', callId: "a" },
    { kind: "tool_result", callId: "a", ok: true, text: "x" },
    { kind: "user", text: "do this", subagent: true },
    { kind: "tool_call", tool: "Bash", text: '{"command":"ls"}', callId: "b", subagent: true },
    { kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"EMBER/1.0","text":"done","kind":"all_done"}', callId: "p" },
    { kind: "user", text: "Your turn ended without a state.", at: "2026-09-28T03:00:00.000Z" },
    { kind: "tool_call", tool: "mcp__stillfail__chat_state", text: '{"kind":"waiting","seconds":60,"for":"CI"}', at: "2026-09-28T03:00:01.000Z" },
    { kind: "assistant", text: "waiting on CI" },
  ];
  const at = (iso: string) => Date.parse(iso);
  const items = presentHistory({ loaded: true, timeline }, { ...cx([], [], []), now: at("2026-09-28T04:00:00.000Z") }).items;
  assert.deepEqual(items.map((i: J) => i.body.kind), ["group", "received", "group", "received", "group", "post", "received", "mark", "text"]);
  // A page that begins mid-turn has no turn for what came before its first prompt; a sub-agent's prompt begins none.
  assert.deepEqual(items.map((i: J) => i.turn === undefined ? null : i.turn.text), [null, "2 步 · 发出 1 条", null, null, null, null, "没发消息", null, null]);
  // Said in the viewer's time (UTC+8 here): today's by its clock alone, an earlier day's with its date.
  assert.deepEqual([items[1].turn.at, items[1].turn.time], [at("2026-09-27T01:02:00.000Z"), "9/27 09:02"]);
  assert.equal(items[6].turn.time, "11:00");
  // How each post and mark left the turn.
  assert.equal(items[5].body.content.ends, "done");
  assert.equal(items[7].body.content.ends, "waiting");
  const state = (kind: string) => presentHistory({ loaded: true, timeline: [{ kind: "tool_call", tool: "mcp__stillfail__chat_state", text: `{"kind":"${kind}"}` }] }, cx([], [], [])).items[0].body.content;
  assert.deepEqual([state("all_done").ends, state("need_human").ends, state("need_human").text, state("odd").ends], ["done", "human", "停下来等人处理", undefined]);
  const post = presentHistory({ loaded: true, timeline: [{ kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"x","text":"t"}' }] }, cx([], [], [])).items[0].body.content;
  assert.equal(post.ends, undefined);
});
