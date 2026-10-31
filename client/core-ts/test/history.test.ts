// The Rust core's history.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import * as format from "../src/format.ts";
import { args, doing } from "../src/activity.ts";
import { activity, hint, parsePrompt, parseTasks, presentHistory, type Context } from "../src/history.ts";
import { holdLanguage } from "../src/i18n.ts";
import { markdown } from "../src/markdown.ts";
import { heardFiles, readItem } from "../src/elsewhere.ts";

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
  slackNames: [["U1", "Ada"]],
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
  // Into Slack's app: at the thread's root, or at a reply in it.
  assert.equal(place.app, "slack://channel?team=T1&id=C1&message=1.000200");
  const reply = format.place(c.threads, "C1/1.000200", c.offsetMin, c.workspaces, "1.000300") as J;
  assert.equal(reply.app, "slack://channel?team=T1&id=C1&message=1.000300&thread_ts=1.000200");
  const unknown = format.place(c.threads, "C9/2.0", c.offsetMin, c.workspaces) as J;
  assert.deepEqual([unknown.name, unknown.url, unknown.app], ["#C9", null, undefined]);
  // A thread whose team the station did not know yet ("slack:<connect id>") has no way into the app.
  const early = format.place([{ ...threads[0], surface: "slack:cl" }], "C1/1.000200", c.offsetMin, c.workspaces) as J;
  assert.equal(early.app, undefined);
});

test("a_feishu_place_is_named_by_its_chat_and_opens_in_feishu_or_lark", () => {
  const threads = [
    { surface: "feishu:codex-bot", channel: "oc_a1b2", threadTs: "om_x1", channelName: "产品群", createdAt: 1_790_000_000_000, sessions: [{ session: "s1" }] },
    { surface: "feishu:lark-bot", channel: "oc_c3", threadTs: "omt_t9", sessions: [] },
  ];
  const workspaces = new Map([
    ["T1", { name: "Acme", url: "https://acme.slack.com/" }],
    ["feishu:lark-bot", { name: "Co", url: format.feishuApplink("lark") }],
  ]);
  assert.deepEqual(format.splitThread("oc_a1b2/om_x1"), ["oc_a1b2", "om_x1"]);
  assert.deepEqual(format.splitThread("oc_a1b2/omt_t9"), ["oc_a1b2", "omt_t9"]);
  assert.equal(format.splitThread("oc_a1b2/om x"), null);
  const p = format.place(threads, "oc_a1b2/om_x1", 480, workspaces) as J;
  assert.deepEqual([p.name, p.surface, p.session, p.url], ["产品群", "feishu", "s1", "https://applink.feishu.cn/client/chat/open?openChatId=oc_a1b2"]);
  const lark = format.place(threads, "oc_c3/omt_t9", 480, workspaces) as J;
  assert.deepEqual([lark.name, lark.surface, lark.url], ["飞书对话", "feishu", "https://applink.larksuite.com/client/chat/open?openChatId=oc_c3"]);
  // Begun when its thread was made (its ts is a message's id, not a time).
  assert.equal(format.threadName(threads, "oc_a1b2", "om_x1", 480)[1], format.threadName([{ channel: "C1", threadTs: "1790000000" }], "C1", "1790000000", 480)[1]);
});

test("a_feishu_person_is_heard_as_a_slack_one_is", () => {
  const [said] = parsePrompt('<message via="feishu" connect="codex-bot" thread="oc_a1/om_1" from="Ada (slack:codex-bot:ou_1)" user="slack:codex-bot:ou_1" ts="om_2">\nhi\n</message>');
  assert.deepEqual([said.length, said[0].slack, said[0].text], [1, true, "hi"]);
});

test("a_prompt_is_the_messages_it_carried_and_embers_words_around_them", () => {
  const [said] = parsePrompt('<message via="slack" connect="cl" you="ember (<@UBOT>)" thread="C1/1.0" from="Ada (U1)" ts="1.2">\nhi\n</message>');
  assert.deepEqual([said.length, said[0].user, said[0].ts, said[0].text], [1, "U1", "1.2", "hi"]);
  const [messages, note] = parsePrompt('Heads up.\n<message via="slack" from="Ada &amp; Co (U1)" ts="1.2" thread="C1/1.0">\nhi <@UBOT>\n</message>\n(Thread C1/1.0 had messages before you were brought in; read them.)');
  assert.equal(note, "Heads up.");
  assert.deepEqual(messages, [{ user: "U1", name: "Ada & Co", ts: "1.2", text: "hi <@UBOT>", thread: "C1/1.0", slack: true, station: false, agent: false }]);
  const [old] = parsePrompt('<slack user="U2" bot ts="3.4">\nyo\n</slack>');
  assert.equal(old[0].user, "U2");
  assert.equal(old[0].text, "yo");
  assert.equal(old[0].agent, true);
});

test("an_agents_letter_reads_as_markdown_a_persons_words_as_they_wrote_them", () => {
  // station instructions.ts: another agent's message is marked `bot`; a person's name may say "bot" and is not one.
  const [said] = parsePrompt('<message via="web" thread="EMBER/1.0" from="Claude Code" bot ts="1.1">\n**根子**：`moves_in`\n</message>\n<message via="web" thread="EMBER/1.0" from="a bot fan (b@x)" ts="1.2">\n**hi**\n</message>');
  assert.deepEqual(said.map((m) => m.agent), [true, false]);
  const h = presentHistory({ timeline: [{ kind: "user", text: '<message via="web" thread="EMBER/1.0" from="Claude Code" bot ts="1.1">\n**根子**：`moves_in`\n</message>\n<message via="web" thread="EMBER/1.0" from="Ada (ada@x)" ts="1.2">\n**hi**\n</message>' }], steps: [] }, cx([], [], []));
  const [letter, person] = h.items[0].body.content.messages;
  assert.deepEqual(letter.md, markdown("**根子**：`moves_in`"));
  assert.equal(person.md, undefined);
});

test("the_instructions_a_continued_session_is_given_carry_no_messages", () => {
  // station instructions.ts `continuedHere`, its instructions showing a message's shape, then the first message.
  const told = 'This session began in a terminal.\n\n<stillfail-instructions>\n- <message via="slack" connect="…" you="name (<@ID>)" thread="CHANNEL/THREAD_TS" from="…" ts="…">…</message> names the conversation.\n</stillfail-instructions>';
  const [messages, note] = parsePrompt(`${told}\n\n<message via="ember" thread="EMBER/1.0" from="Ada (ada@x)" ts="2.0">\n具体什么问题\n</message>`);
  assert.deepEqual(messages.map((m) => [m.thread, m.text]), [["EMBER/1.0", "具体什么问题"]]);
  assert.equal(note, told);
  assert.equal(readItem(0, { kind: "user", text: told, at: "2026-10-26T06:14:00Z" }), null);
});

test("a_message_the_station_cut_short_is_still_read_as_one", () => {
  const cut = '<message via="ember" from="ember" ts="9.1">\nRemote task t1 on mini1: {"job":{"state":"done"\n… (1505 more characters)';
  const [messages, note] = parsePrompt(cut);
  assert.equal(note, "");
  assert.deepEqual(
    messages.map((m) => [m.station, m.text]),
    [[true, 'Remote task t1 on mini1: {"job":{"state":"done"\n… (1505 more characters)']],
  );
  // Words not cut by the station and missing their closing tag are not a message.
  assert.equal(parsePrompt('<message via="ember" from="ember" ts="9.1">\nhi')[0].length, 0);
});

test("a_station_notice_is_a_jobs_words_or_an_event_in_a_line", () => {
  const said = "OVER BUDGET: run 1 took 301 s\n\njobs:\n  +   0 s    13 s  plan";
  const notices = [
    `Job "ci-time-watch" (job_2b767635) says: ${said}`,
    'Service "web" (job_1, port 5173) says: up',
    'Job "shot" (job_2) ended with exit code 1.\nIts last lines:\n```\nboom\n```',
    'Service "web" (job_1, port 5173) ended with a signal; the station starts it again in 2 s.',
    'Job "shot" (job_2) was stopped by Ada from still.fail\'s page.',
    'The station restarted; Job "shot" (job_2) could not be started again: no such file',
    'The chat you opened, "Fix CI" (https://still.fail/chats/c-1), needs a person: pick one. They are asked there; help if you can, or wait. Read it with chat_read; write to its agent with session_send to its link.',
    'Remote task t1 on mini1: {"job":{"state":"running"}}',
  ];
  const text = notices.map((n) => `<message via="ember" from="ember" ts="9.1">\n${n}\n</message>`).join("\n");
  assert.equal(parsePrompt(text)[0][0].station, true);
  const h = presentHistory({ loaded: true, timeline: [{ kind: "user", text }] }, cx([], [], []));
  const { tasks, messages } = h.items[0].body.content;
  assert.deepEqual(messages.map((m: J) => [m.key, m.notice, m.from.name, m.text]), [
    ["9.1.0", "job", "ci-time-watch", said],
    ["9.1.1", "job", "web", "up"],
    ["9.1.7", "stillfail", "still.fail", notices[7]],
  ]);
  assert.deepEqual(tasks.map((x: J) => [x.text, x.agent, x.failed, x.result]), [
    ["任务已退出（退出码 1）：shot", false, true, "boom"],
    ["服务被信号终止，正在重新启动：web", false, true, null],
    ["任务已被 Ada 停止：shot", false, false, null],
    ["任务无法重新启动：shot", false, true, "no such file"],
    ["对话需要你处理：Fix CI", true, false, "pick one"],
  ]);
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
  assert.deepEqual(received.tasks, [{ text: "后台命令失败（退出码 2）：Run tests", agent: false, failed: true, result: null, md: null, line: null }]);
});

test("a_line_standing_for_words_closed_is_their_first_words_without_marks", () => {
  const note = '<task-notification>\n<task-id>b1</task-id>\n<tool-use-id>toolu_1</tool-use-id>\n<output-file>/tmp/b1.output</output-file>\n<status>completed</status>\n<summary>Agent "Map it" finished</summary>\n<result>## Found\n**it**</result>\n</task-notification>';
  const timeline = [
    { kind: "user", text: note },
    { kind: "thinking", text: "**Planning the fix**\n\nRead `list.mbt` first." },
    { kind: "tool_call", tool: "Read", text: '{"file_path":"/a.ts"}', callId: "a" },
    { kind: "tool_result", callId: "a", ok: true, text: "x" },
    { kind: "assistant", text: "**Done.** The [list](https://a.b/c) is fixed.\n\n- one" },
  ];
  const items = presentHistory({ loaded: true, timeline }, cx([], [], [])).items;
  assert.deepEqual(items.map((i: J) => i.body.kind), ["received", "group", "text"]);
  // A sub-agent's answer, a thought (read as Markdown, drawn so), the agent's own words: each its line closed.
  assert.equal(items[0].body.content.tasks[0].line, "Found");
  const thought = items[1].body.content.rows[0].content;
  assert.deepEqual([thought.first, thought.md], ["Planning the fix", markdown(thought.text)]);
  assert.equal(items[2].body.content.line, "Done. The list is fixed.");
});

test("boundaries_stand_alone_and_the_work_between_folds_into_a_group", () => {
  const threads = [{ surface: "slack:T1", channel: "C1", threadTs: "1.0", channelName: "ops", sessions: [{ session: "s1" }] }];
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
      { kind: "tool_call", tool: "mcp__ember__chat_post", text: '{"to":"C1/1.0","text":"<@U1> done","kind":"block"}', callId: "d" },
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
  // What 只看收发 leaves out: its steps and thoughts, and its words to itself; what came in and went out, and how it ended, stay.
  assert.deepEqual(items.map((i: J) => i.work === true), [false, true, false, false, true]);
  const m = items[0].body.content.messages[0];
  assert.deepEqual([m.from.name, m.text, m.place.name, m.place.session], ["你", "hi @ds-ember", "Acme#ops", "s1"]);
  // A message from Slack opens there at itself, in its thread; what was posted, at the thread.
  assert.equal(m.place.app, "slack://channel?team=T1&id=C1&message=1.2&thread_ts=1.0");
  assert.equal(items[2].body.content.place.app, "slack://channel?team=T1&id=C1&message=1.0");
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
  assert.deepEqual([items[2].body.content.block, items[2].body.content.place.name, items[2].body.content.ends], [true, "Acme#ops", "human"]);
  // A Slack person it mentions, by the name the station's agents heard them by.
  assert.deepEqual([items[2].body.content.text, items[2].body.content.md], ["@Ada done", markdown("@Ada done")]);
  assert.deepEqual([items[3].body.content.text, items[3].body.content.ends], ["标记为已完成", "done"]);
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
  // An agent that went on working after its mark waits no more from its next call (another mark is one); what it posts
  // as its turn ends, and a sub-agent's work, do not end it.
  const then = (...more: J[]) => {
    const timeline: J[] = [{ kind: "tool_call", tool: "mcp__stillfail__chat_state", text: '{"kind":"waiting","seconds":600}', at: "2026-09-27T00:00:00.000Z" }, ...more];
    return presentHistory({ loaded: true, timeline }, cx(threads, members, slack)).items[0].body.content.wait.until;
  };
  const later = (k: number) => `2026-09-27T00:00:0${k}.000Z`;
  assert.equal(then({ kind: "assistant", text: "checking", at: later(1) }, { kind: "tool_call", tool: "Bash", text: '{"command":"gh pr checks"}', at: later(3) }), Date.parse(later(3)));
  assert.equal(then({ kind: "tool_call", tool: "mcp__stillfail__chat_state", text: '{"kind":"waiting","seconds":60}', at: later(4) }), Date.parse(later(4)));
  assert.equal(then({ kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"C/1","text":"waiting on CI"}', at: later(2) }, { kind: "assistant", text: "waiting", at: later(3) }), null);
  assert.equal(then({ kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"C/1","text":"done","kind":"all_done"}', at: later(2) }), Date.parse(later(2)));
  assert.equal(then({ kind: "tool_call", tool: "Bash", text: '{"command":"ls"}', at: later(5), subagent: true }), null);
  assert.deepEqual(h.live, [{ id: "s", text: "正在思考…" }]);
  assert.equal(h.phase.text, "正在启动 Codex");
  // The model answering is said in the person's language, as the chat's activity says it.
  assert.equal(presentHistory({ ...live, phase: { phase: "responding", since: 5 } }, cx(threads, members, slack)).phase.text, "思考中");
  assert.equal(h.usage[4].value, "50%");
  assert.equal(h.usageLine, "调用 3 次 · 输入 2K（缓存 50%） · 输出 50");
  assert.equal(h.edge, "已到会话开头");
  // A station since tells the context and the cost too.
  const more = (usage: J) => presentHistory({ ...live, usage: { ...live.usage, ...usage } }, cx(threads, members, slack));
  const now2 = more({ contextTokens: 86_000, cost: 3.214, unpricedCalls: 0 });
  assert.deepEqual(now2.usage.slice(5), [{ label: "上下文", value: "86K" }, { label: "费用估算", value: "$3.21" }]);
  assert.equal(now2.usageLine, "调用 3 次 · 输入 2K（缓存 50%） · 输出 50 · 上下文 86K · 约 $3.21");
  assert.equal(more({ contextTokens: 86_000, contextWindow: 258_000, cost: 1, unpricedCalls: 1 }).usage[5].value, "86K / 258K（33%）");
  assert.equal(more({ contextTokens: 1, cost: 1, unpricedCalls: 1 }).usage[6].value, "≥$1.00");
  assert.equal(more({ contextTokens: 1, cost: 0, unpricedCalls: 3 }).usage[6].value, "该模型无价目");
});

test("an_empty_history_says_why", () => {
  const edge = (live: J, started: boolean) => presentHistory(live, { ...cx([], [], []), started }).edge;
  assert.equal(edge({ loaded: false }, true), "正在读取执行历史");
  assert.equal(edge({ loaded: true }, false), "运行时尚未开始此会话");
  assert.equal(edge({ loaded: true, offline: true }, true), "station 离线，此设备上暂无该会话的执行历史");
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
  assert.deepEqual([h.more, h.edge, h.empty], [true, "正在读取更早的执行历史", false]);
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

test("a_result_written_before_its_call_still_answers_that_call", () => {
  // Claude Code can write a quick call's result (ToolSearch's) before the call it answers: the result goes to its call
  // by id, not to the call before it, and neither shows running.
  const timeline = [
    { kind: "user", text: "go" },
    { kind: "tool_call", tool: "Skill", text: '{"skill":"x"}', callId: "a" },
    { kind: "tool_result", callId: "b", ok: true, text: "tools" },
    { kind: "tool_result", callId: "a", ok: true, text: "skill" },
    { kind: "tool_call", tool: "ToolSearch", text: '{"query":"select:mcp__stillfail__chat_post"}', callId: "b" },
  ];
  const g = presentHistory({ loaded: true, timeline }, cx([], [], [])).items.find((i: J) => i.body.kind === "group").body.content;
  assert.equal(g.pending, 0);
  assert.deepEqual(g.rows.map((r: J) => r.content.result), ["skill", "tools"]);
  assert.equal(activity({ timeline, phase: { phase: "thinking" } }).now.key, "think");
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
  assert.deepEqual(items.map((i: J) => i.turn === undefined ? null : i.turn.text), [null, "2 步 · 发出 1 条", null, null, null, null, "未发消息", null, null]);
  // Said in the viewer's time (UTC+8 here): today's by its clock alone, an earlier day's with its date.
  assert.deepEqual([items[1].turn.at, items[1].turn.time], [at("2026-09-27T01:02:00.000Z"), "9/27 09:02"]);
  assert.equal(items[6].turn.time, "11:00");
  // How each post and mark left the turn.
  assert.equal(items[5].body.content.ends, "done");
  assert.equal(items[7].body.content.ends, "waiting");
  const state = (kind: string) => presentHistory({ loaded: true, timeline: [{ kind: "tool_call", tool: "mcp__stillfail__chat_state", text: `{"kind":"${kind}"}` }] }, cx([], [], [])).items[0].body.content;
  assert.deepEqual([state("all_done").ends, state("need_human").ends, state("need_human").text, state("odd").ends], ["done", "human", "已暂停，等待人工处理", undefined]);
  const post = presentHistory({ loaded: true, timeline: [{ kind: "tool_call", tool: "mcp__stillfail__chat_post", text: '{"to":"x","text":"t"}' }] }, cx([], [], [])).items[0].body.content;
  assert.equal(post.ends, undefined);
});

test("a_task_on_another_station_says_where_it_runs_and_what", () => {
  const studio = "d2e33e62a1f88dd30e759c734b6604599a6e4024dbb926b1cd81b99c42da4956";
  const call = (id: string, a: J) => ({ kind: "tool_call", tool: "mcp__stillfail__station_task", callId: id, text: JSON.stringify({ station: studio, ...a }), at: "2026-10-18T00:00:00Z" });
  const done = (id: string) => ({ kind: "tool_result", callId: id, ok: true, text: "{}", at: "2026-10-18T00:00:01Z" });
  const live = {
    timeline: [
      { kind: "user", text: "check it" },
      call("a", { action: "prepare", key: "check", name: "typecheck web", command: "exec 2>&1\npnpm -C web tsc" }),
      done("a"),
      call("b", { action: "start", key: "check" }),
      done("b"),
    ],
  };
  const g = presentHistory(live, { ...cx([], [], []), stations: new Map([[studio, "Studio"]]) }).items[1].body.content;
  assert.deepEqual(g.rows.map((r: J) => r.content.said), ["在 Studio 上准备 typecheck web", "在 Studio 上运行 typecheck web"]);
  assert.equal(g.summary, "在 Studio 上运行 typecheck web · 共 2 项");
});

test("a_slack_messages_files_are_its_files_not_its_words", () => {
  const path = "/w/s/workspace/uploads/2026-10-27T09-15-34-F0-image.png";
  const text = `看这个\n\nAttached files:\n- ${path} (image.png, 1709315 bytes)\n- /w/s/workspace/uploads/b (a (1), b.txt, 3 bytes)`;
  const prompt = `<message via="slack" connect="c" thread="C1/1.0" from="Ada (U1)" ts="2.0">\n${text}\n</message>`;
  const read = readItem(0, { kind: "user", text: prompt, at: "2026-10-27T01:15:34Z" }) as J;
  assert.deepEqual(heardFiles(read.said[0].text), {
    text: "看这个",
    files: [{ path, name: "image.png", size: 1709315 }, { path: "/w/s/workspace/uploads/b", name: "a (1), b.txt", size: 3 }],
  });
  // Files alone: no words.
  assert.deepEqual(heardFiles(`Attached files:\n- ${path} (image.png, 9 bytes)`), { text: "", files: [{ path, name: "image.png", size: 9 }] });
  // Words that only look like it are words.
  for (const words of ["Attached files:\n- see below", "a\nAttached files:\n- /p (x, 1 bytes)"]) assert.deepEqual(heardFiles(words), { text: words, files: [] });
});
