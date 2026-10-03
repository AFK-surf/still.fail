// client/core/src/history.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import * as format from "../src/format.ts";
import { args, hint, parsePrompt, presentHistory, type Context } from "../src/history.ts";
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
  assert.equal(g.title, "读取 1 个文件、运行 1 条命令");
  assert.deepEqual([g.failures, g.pending], [1, 1]);
  assert.equal(g.steps[0].meta, "2 秒");
  assert.equal(g.steps[1].meta, "进行中");
  assert.equal(g.thinking[0].first, "plan it");
  assert.deepEqual(items[1].entries, [1, 6]);
  assert.deepEqual([items[2].body.content.block, items[2].body.content.place.name], [true, "#ops"]);
  assert.equal(items[3].body.content.text, "标记为做完了");
  const waits = (a: string, next: string | null) => {
    const timeline: J[] = [{ kind: "tool_call", tool: "mcp__ember__chat_state", text: a, at: "2026-09-27T00:00:00.000Z" }];
    if (next !== null) timeline.push({ kind: "user", text: '<message via="ember">done</message>', at: next });
    return presentHistory({ loaded: true, timeline }, cx(threads, members, slack)).items[0].body.content;
  };
  const back = waits('{"kind":"waiting","seconds":150}', "2026-09-27T00:01:20.000Z");
  assert.equal(back.text, "等待了 1m 20s / 2m 30s");
  assert.deepEqual(back.wait, { since: 1790467200000, until: 1790467280000, seconds: 150 });
  assert.equal(waits('{"kind":"waiting","seconds":60}', "2026-09-27T01:00:00.000Z").text, "等待了 1m / 1m");
  const now = waits('{"kind":"waiting","seconds":600}', null);
  assert.deepEqual([now.text, now.wait.until], ["等待中，最长 10m", null]);
  assert.deepEqual(h.live, [{ id: "s", text: "正在思考…" }]);
  assert.equal(h.phase.text, "正在启动 Codex");
  assert.equal(h.usage[4].value, "50%");
  assert.equal(h.usageLine, "调用 3 次 · 输入 2K（缓存 50%） · 输出 50");
  assert.equal(h.edge, "已到 Session 开始处");
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
