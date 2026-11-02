// The Rust core's present.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { holdLanguage } from "../src/i18n.ts";
import * as p from "../src/present.ts";
import { packetsSince } from "../src/station/topics.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const GIB = 1024 ** 3;

test("a_connection_is_said_in_words_and_only_what_is_off_is_coloured", () => {
  const unnamed = () => null;
  assert.equal(p.net(null, unnamed), null);
  const sample = (rtt: number, sent: number, lost: number) => ({ at: 0, rttMs: rtt, rxBps: 1_468_006, txBps: 83_968, sent, lost });
  const raw: J = { path: "direct", rttMs: 38.4, rxBytes: 222_298_112, txBytes: 10_066_329, samples: [sample(40, 50, 0), sample(38.4, 50, 0)] };
  let shown = p.net(raw, unnamed);
  assert.equal(shown.path, "直连");
  assert.equal(shown.via, "direct");
  assert.deepEqual(shown.rtt, { text: "38 ms", level: "ok" });
  assert.deepEqual(shown.rttHistory, [40, 38.4]);
  assert.deepEqual([shown.down, shown.up], ["1.4 MB/s", "82 KB/s"]);
  assert.equal(shown.total, "本次共 ↓ 212 MB · ↑ 9.6 MB");
  assert.deepEqual([shown.downTotal, shown.upTotal], ["212 MB", "9.6 MB"]);
  assert.equal(shown.loss, null);
  const daily = { ...raw, todayRxBytes: 1_073_741_824, todayTxBytes: 52_428_800 };
  shown = p.net(daily, unnamed);
  assert.equal(shown.total, "今天共 ↓ 1.0 GB · ↑ 50 MB");
  assert.deepEqual([shown.downTotal, shown.upTotal], ["1.0 GB", "50 MB"]);

  const relay: J = { path: "relay", relay: "relay.still.fail", rttMs: 286, rxBytes: 0, txBytes: 0, samples: [sample(1200, 200, 10)] };
  shown = p.net(relay, unnamed);
  assert.equal(shown.path, "中继 relay.still.fail");
  assert.equal(shown.via, "relay");
  const named = (host: string) => (host === "relay.still.fail" ? "北京" : null);
  assert.equal(p.net(relay, named).path, "北京中继");
  assert.equal(shown.rtt.level, "ok");
  assert.deepEqual(shown.loss, { text: "丢包 5.0%", level: "amber" });
  // A quiet minute: too few packets for a share of them to say anything.
  assert.equal(p.net({ ...relay, samples: [sample(1200, 60, 20)] }, unnamed).loss, null);
  const measured = { measuring: false, relays: [{ relay: "relay.still.fail", rttMs: 11_000 }, { relay: "hk.test", rttMs: 82 }, { relay: "cf.test", rttMs: null }], moved: "hk.test" };
  const viaHk = { path: "relay", relay: "hk.test", rttMs: 90, rxBytes: 0, txBytes: 0, samples: [], measured };
  assert.deepEqual(p.net(viaHk, named).measured, {
    measuring: false,
    relays: [
      { name: "北京", rtt: { text: "11.0 s", level: "red" }, current: false },
      { name: "hk.test", rtt: { text: "82 ms", level: "ok" }, current: true },
      { name: "cf.test", rtt: null, current: false },
    ],
    moved: "hk.test",
  });
  shown = p.net({ path: null, rttMs: 1500, rxBytes: 0, txBytes: 0, samples: [] }, unnamed);
  assert.deepEqual([shown.path, shown.via, shown.down], ["正在选择线路", "choosing", "—"]);
  assert.deepEqual(shown.rtt, { text: "1.5 s", level: "red" });
});

test("a_rows_people_are_said_in_words_who_started_it_first", () => {
  const me = { id: "me@x.com", email: "me@x.com" };
  let row: J = { creator: { id: "wang@x.com", name: "小王" }, people: [{ id: "lina@x.com", name: "Lina" }, { id: "me@x.com", name: "Me" }] };
  row = p.rowPeople(row, me, [], []);
  assert.equal(row.peopleText, "小王 发起 · Lina、你");
  row = { people: [{ id: "lina@x.com", name: "Lina" }] };
  row = p.rowPeople(row, me, [], []);
  assert.equal(row.peopleText, "Lina");
});

test("profile_recovery_follows_states_and_clears_after_success", () => {
  let q: J = { access: { kind: "subscription" }, check: { state: "login" }, quota: { state: "unavailable" } };
  q = p.profile(q);
  assert.equal(q.trouble.action, "login");
  q.machine = true;
  q = p.profile(q);
  assert.equal(q.trouble.action, "command");
  q.check.state = "ok";
  q = p.profile(q);
  assert.equal(q.trouble.action, "quota");
  assert.equal(q.checkText, "可用");
  assert.equal(q.trouble.detail, "暂时无法获取额度");
  q.quota.state = "ok";
  q = p.profile(q);
  assert.equal(q.trouble, null);
  q.quota.state = "blocked";
  q = p.profile(q);
  assert.equal(q.trouble.title, "账号被停用");
  assert.equal(q.checkTone, "red");
});

test("a_profile_says_what_it_can_do_from_where_its_provider_speaks", () => {
  const text = (q: J) => {
    q = p.profile(q);
    return [q.access?.kind ?? "", q.usesText ?? ""];
  };
  assert.deepEqual(text({ runtimes: [], access: { kind: "env", provider: "deepseek" } }), ["api-provider", "自动决策"]);
  assert.deepEqual(text({ runtimes: ["claude"], access: { kind: "api-provider", provider: "openrouter" } }), ["api-provider", "Claude Code · 自动决策"]);
  assert.equal(text({ runtimes: ["codex"], access: { kind: "api-provider", provider: "azure-openai", endpoint: "https://x.openai.azure.com/openai/v1" } })[1], "Codex");
  assert.equal(text({ runtimes: ["claude", "codex"], access: { kind: "opencode-go" } })[1], "Claude Code · Codex · 自动决策");
  assert.equal(text({ runtimes: ["claude"], access: { kind: "anthropic-api" } })[1], "Claude Code");
  assert.equal(text({ runtimes: ["claude", "dsh"], access: { kind: "anthropic-api" } })[1], "Claude Code · DeepSeek Harness");
  assert.deepEqual(text({ runtimes: ["grok", "dsh", "codex"], access: { kind: "api-provider", provider: "xai" } }), ["api-provider", "Codex · DeepSeek Harness · Grok Build"]);
  assert.deepEqual(text({ runtimes: ["grok"], access: { kind: "subscription" } }), ["subscription", ""]);
  assert.deepEqual(text({ runtimes: ["cursor"], access: { kind: "subscription" } }), ["subscription", ""]);
  assert.deepEqual(text({ runtimes: ["devin"], access: { kind: "subscription" } }), ["subscription", ""]);
  assert.equal(text({ runtimes: ["dsh", "codex", "claude"], access: { kind: "opencode-go" } })[1], "Claude Code · Codex · DeepSeek Harness · 自动决策");
  assert.deepEqual(text({ runtimes: ["dsh"], access: { kind: "api-provider", provider: "deepseek" } }), ["api-provider", "DeepSeek Harness · 自动决策"]);
  assert.deepEqual(text({ runtimes: ["dsh"], access: { kind: "env" } }), ["env", ""]);
  assert.deepEqual(text({ runtimes: ["codex"], access: { kind: "env" } }), ["env", ""]);
  assert.equal(text({ runtimes: ["codex"], access: { kind: "env" }, check: { decision: { state: "ready" } } })[1], "Codex · 自动决策");
  const canName = (provider: string) => {
    let q: J = { runtimes: [], access: { kind: "env", provider } };
    q = p.profile(q);
    return q.canAddModel === true;
  };
  assert.ok(!canName("jev") && canName("minimax") && canName("deepseek"));
  let jev: J = { runtimes: [], access: { kind: "env", provider: "jev" }, check: { state: "ok", decision: { state: "ready", detail: "已识别 1 个决策模型", models: ["jev-latest"] } } };
  jev = p.profile(jev);
  assert.deepEqual([jev.decisionOnly, jev.decisionModels, jev.decisionText], [true, ["jev-latest"], "已识别 1 个决策模型"]);
  // Said from the station's reason, not its Chinese detail.
  let found: J = { runtimes: [], access: { kind: "env", provider: "jev" }, check: { state: "ok", decision: { state: "ready", detail: "x", reason: "found", models: ["jev-latest", "jev-mini"] } } };
  found = p.profile(found);
  assert.equal(found.decisionText, "已识别 2 个决策模型");
  let waiting: J = { runtimes: [], access: { kind: "env", provider: "jev" }, check: { state: "ok" } };
  waiting = p.profile(waiting);
  assert.deepEqual([waiting.decisionModels, waiting.decisionText], [[], "正在识别决策模型"]);
  let x: J = { runtimes: [], access: { kind: "env", provider: "xiaomi" }, check: { state: "failed" } };
  x = p.profile(x);
  assert.deepEqual([x.providerName, x.trouble.action], ["Xiaomi MiMo", "key"]);
});

test("profile_recovery_offers_only_the_editor_for_its_access_kind", () => {
  for (const [kind, action] of [["anthropic-api", "key"], ["opencode-go", "key"], ["api-provider", "key"], ["env", "env"], ["subscription", "check"]]) {
    const issue = p.profileTrouble({ access: { kind }, check: { state: "failed", detail: "timeout" } });
    assert.equal(issue.action, action);
    assert.equal(issue.detail, "timeout");
  }
  assert.equal(p.profileTrouble({}), null);
});

test("a_session_stands_where_its_process_and_last_turn_say", () => {
  const st = p.sessionStatus;
  assert.equal(st({ process: "running" }), "running");
  assert.equal(st({ process: "warm", pending: 1 }), "queued");
  assert.equal(st({ lastTurn: { declared: "block", outcome: "completed" } }), "block");
  assert.equal(st({ lastTurn: { declared: "block", ending: "need_decision", outcome: "completed" } }), "block");
  assert.equal(st({ lastTurn: { declared: "block", ending: "need_help", outcome: "completed" } }), "block");
  assert.equal(st({ lastTurn: { declared: "final", ending: "all_done", outcome: "completed" } }), "final");
  assert.equal(st({ lastTurn: { declared: "final", outcome: "completed" } }), "final");
  assert.equal(st({ process: "warm", lastTurn: { declared: "waiting", ending: "waiting", outcome: "completed" } }), "running");
  assert.equal(st({ process: "warm", lastTurn: { declared: "waiting", outcome: "completed" } }), "running");
  assert.equal(st({ lastTurn: { outcome: "completed" } }), "unexpected");
  // A turn just begun, read before the station's process states caught up: running, not stopped.
  assert.equal(st({ process: "cold", lastTurn: { outcome: null, declared: null, startedAt: 1, endedAt: null } }), "running");
  const waits = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600 } };
  assert.deepEqual(p.waiting(waits), { since: 5, seconds: 600, text: "等待中" });
  assert.deepEqual(p.waiting({ process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5 } }), { since: 5, seconds: null, text: "等待中" });
  assert.equal(p.waiting({ process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitFor: "CI 跑完" } }).text, "等待：CI 跑完");
  let watching: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600 }, watch: { names: ["盯 CI"], since: 1, at: 5 } };
  watching = p.session(watching);
  assert.deepEqual([watching.statusText, watching.mark], ["监控中", null]);
  // Waiting on something else while a watch runs: what it waits on, at work, not the watch over it.
  let other: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600, waitFor: "读中继的日志", waitWatch: false }, watch: { names: ["盯 CI"], since: 1, at: 5 } };
  other = p.session(other);
  assert.deepEqual([other.statusText, other.statusLead, other.mark], ["等待：读中继的日志", "wait", "run"]);
  let saidWatch: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600, waitFor: "盯 CI", waitWatch: true }, watch: { names: ["盯 CI"], since: 1, at: 5 } };
  saidWatch = p.session(saidWatch);
  assert.deepEqual([saidWatch.statusText, saidWatch.statusLead, saidWatch.mark], ["监控中", "watch", null]);
  let plain: J = structuredClone(waits);
  plain = p.session(plain);
  assert.equal(plain.statusText, "等待中");
  let said: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600, waitFor: "CI 跑完" } };
  said = p.session(said);
  assert.equal(said.statusText, "等待：CI 跑完");
  assert.equal(p.waiting({ process: "running", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5 } }), null);
  assert.equal(p.waiting({ process: "warm", pending: 1, lastTurn: { declared: "waiting", endedAt: 5 } }), null);
  assert.equal(st({}), "idle");
});

test("a_sessions_context_is_compacted_or_cleared_by_hand_between_turns_once_it_has_one", () => {
  const can = (s: J) => { const v = p.session(s); return [v.canCompact, v.canClear]; };
  const both = ["compact", "clear"];
  assert.deepEqual(can({ process: "warm", runtimeSessionId: "r1", contextActions: both }), [true, true]);
  assert.deepEqual(can({ process: "cold", runtimeSessionId: "r1", contextActions: ["clear"] }), [false, true]);
  assert.deepEqual(can({ process: "running", runtimeSessionId: "r1", contextActions: both }), [false, false]);
  assert.deepEqual(can({ process: "warm", running: true, runtimeSessionId: "r1", contextActions: both }), [false, false]);
  // None yet (a new chat, one just cleared), or a station from before that can do neither.
  assert.deepEqual(can({ process: "cold", runtimeSessionId: null, contextActions: both }), [false, false]);
  assert.deepEqual(can({ process: "warm", runtimeSessionId: "r1" }), [false, false]);
});

test("an_account_its_provider_refuses_says_so_whatever_its_check_found", () => {
  let q: J = { check: { state: "ok" }, quota: { state: "blocked", windows: [] } };
  q = p.profile(q);
  assert.deepEqual([q.checkText, q.checkTone], ["已停用", "red"]);
  let ok: J = { check: { state: "ok" }, quota: { state: "unavailable", windows: [] } };
  ok = p.profile(ok);
  assert.equal(ok.checkText, "可用");
});

test("a_profiles_check_line_leaves_out_the_address_that_is_its_name", () => {
  let q: J = { name: "claude5@example.com", check: { state: "ok", detail: "已登录，claude5@example.com，max" } };
  q = p.profile(q);
  assert.equal(q.checkLine, "已登录，max");
  let last: J = { name: "claude5@example.com", check: { state: "ok", detail: "已登录，claude5@example.com" } };
  last = p.profile(last);
  assert.equal(last.checkLine, "已登录");
  let other: J = { name: "主账号", check: { state: "ok", detail: "Signed in, a@example.com" } };
  other = p.profile(other);
  assert.equal(other.checkLine, "Signed in, a@example.com");
});

test("a_rows_state_puts_block_first", () => {
  const agents = [{ lastTurn: { outcome: "failed" } }, { process: "running" }, { lastTurn: { declared: "block" } }];
  assert.equal(p.rowState(agents), "block");
  assert.equal(p.rowState(agents.slice(0, 2)), "run");
  assert.equal(p.rowState([{ lastTurn: { declared: "final" } }]), null);
});

test("the_last_speaker_is_named_and_an_agents_state_rides_on_it", () => {
  const me = { id: "a@x.com", email: "a@x.com" };
  const members = [{ email: "b@x.com", name: "阿二", picture: "https://p/b" }];
  const row = (kind: string, author: string): J => ({
    agents: [{ key: "k", model: "gpt-6-astra", runtime: "codex", lastTurn: { declared: "block" } }],
    last: { authorKind: kind, author, authorName: null, text: "hi", agentIdentity: { model: "deepseek-flash" } },
  });
  const agent = p.lastBy(row("agent", "k"), me, [], members);
  assert.deepEqual([agent.name, agent.state], ["DeepSeek Flash", "block"]);
  const legacy = row("agent", "k");
  delete legacy.last.agentIdentity;
  assert.equal(p.lastBy(legacy, me, [], members).name, "GPT-6 Astra");
  const other = p.lastBy(row("person", "b@x.com"), me, [], members);
  assert.deepEqual([other.name, other.picture, other.mine], ["阿二", "https://p/b", false]);
  assert.equal(p.lastBy(row("person", "A@x.com"), me, [], members).name, "你");
  assert.equal(p.lastBy(row("person", "U7"), me, ["U7"], members).mine, true);
  // A Slack person: the picture their Slack shows, over their workspace account's.
  const slack = row("person", "b@x.com");
  slack.last.authorPicture = "https://avatars.slack-edge.com/b_72.png";
  assert.equal(p.lastBy(slack, me, [], members).picture, "https://avatars.slack-edge.com/b_72.png");
});

test("a_profiles_models_come_by_series", () => {
  let q: J = { models: ["claude-opus-5-5", "claude-sonnet-5", "claude-opus-4-8", "my-model", "claude-fable-5-1"], check: { models: ["claude-sonnet-5", "claude-opus-4-8", "claude-opus-5-5", "claude-fable-5-1"] } };
  q = p.profile(q);
  assert.deepEqual(q.series, [
    { name: "Fable", models: ["claude-fable-5-1"] },
    { name: "Opus", models: ["claude-opus-5-5", "claude-opus-4-8"] },
    { name: "Sonnet", models: ["claude-sonnet-5"] },
    { name: "其他", models: ["my-model"] },
  ]);
});

test("how_a_turn_ended_says_itself_in_words", () => {
  const words = (turn: J) => {
    let s: J = { process: "warm", lastTurn: turn };
    s = p.session(s);
    return s.statusText;
  };
  assert.equal(words({ declared: "final", ending: "all_done", outcome: "completed" }), "已完成");
  assert.equal(words({ declared: "block", ending: "need_help", need: "要 Stripe 的测试 key", outcome: "completed" }), "需要你处理：要 Stripe 的测试 key");
  assert.equal(words({ declared: "block", outcome: "completed" }), "需要你处理");
  assert.equal(words({ declared: "block", ending: "need_decision", outcome: "completed" }), "需要你处理");
  assert.equal(words({ outcome: "failed", detail: "rate_limit: You've hit your limit" }), "出错：额度已用完");
  assert.equal(words({ outcome: "failed", detail: "auth: 401" }), "出错：登录失效");
  assert.equal(words({ outcome: "aborted" }), "出错：被停止");
  assert.equal(words({ outcome: "completed" }), "出错：意外停止");
  // Without its lead (the 待处理 list's line, its dot says that much): what it needs, why it stopped.
  const what = (turn: J) => p.rowStateLine({ agents: [p.session({ process: "warm", lastTurn: turn })] })?.[2];
  assert.equal(what({ declared: "block", ending: "need_help", need: "要 Stripe 的测试 key", outcome: "completed" }), "要 Stripe 的测试 key");
  assert.equal(what({ declared: "block", outcome: "completed" }), "需要你处理");
  assert.equal(what({ outcome: "failed", detail: "auth: 401" }), "登录失效");
  assert.equal(what({ outcome: "aborted" }), "被停止");
  assert.equal(what({ outcome: "completed" }), "意外停止");
  let decided: J = { process: "warm", lastTurn: { declared: "block", ending: "need_decision", outcome: "completed" } };
  decided = p.session(decided);
  assert.equal(decided.mark, "block");
});

test("a_decision_agent_passes_the_chat_shape", () => {
  let s: J = { key: "ember:c-decision", runtime: "codex", process: "warm", pending: 0, lastTurn: { kind: "message", startedAt: 1, declared: "block", ending: "need_decision", outcome: "completed" } };
  s = p.session(s);
  const agent = { status: p.shownStatus(s), badge: p.markOf(s), session: s, profiles: [], choices: [], attention: [], turns: [], threads: [], jobs: [] };
  const checked = conform("ChatAgent", agent) as J;
  assert.ok("ok" in checked, JSON.stringify(checked));
  assert.equal(checked.ok.status, "block");
  assert.equal(checked.ok.badge, "block");
  assert.equal(checked.ok.session.statusText, "需要你处理");
  const legacy = { ...checked.ok, status: "decision" };
  assert.equal((conform("ChatAgent", legacy) as J).ok.status, "decision");
});

test("a_chat_with_nothing_left_is_settled_and_says_where_it_stands", () => {
  const agent = (turn: J, process: string): J => {
    let a: J = { key: "k", process, pending: 0, lastTurn: turn };
    a = p.session(a);
    return a;
  };
  const done = agent({ declared: "final", ending: "all_done", outcome: "completed" }, "warm");
  const helped = agent({ declared: "block", ending: "need_help", need: "要 key", outcome: "completed" }, "warm");
  const waits = agent({ declared: "waiting", ending: "waiting", waitFor: "CI 跑完", outcome: "completed", endedAt: 5 }, "warm");
  const works = agent(null, "running");
  const row = (agents: J[], unread: boolean): J => ({ agents: structuredClone(agents), unread });
  assert.ok(p.settled(row([done], false)));
  // Pinned, it is never offered for the archive; nor one the viewer kept (保留), pinned or not.
  const pinned = row([done], false);
  pinned.pinned = 1700000000000;
  assert.ok(p.pinned(pinned));
  assert.ok(!p.archivable(pinned));
  assert.ok(!p.pinned(row([done], false)));
  const kept = row([done], false);
  kept.archiveReminderDismissed = true;
  assert.ok(!p.archivable(kept));
  assert.equal(p.rowStateText(row([done], false)), "已完成");
  // A recommendation shows in how the row is drawn (archivable, below), not in its words.
  const recommended = row([done], false);
  recommended.archiveRecommended = true;
  assert.equal(p.rowStateText(recommended), "已完成");
  // Where the station's archive review is on, a done chat is offered for the archive only once it recommended so.
  assert.ok(p.archivable(row([done], false)));
  const reviewed = row([done], false);
  reviewed.archiveReviewed = true;
  assert.ok(!p.archivable(reviewed));
  reviewed.archiveRecommended = true;
  assert.ok(p.archivable(reviewed));
  assert.ok(!p.archivable(kept));
  // Offered to archive as the viewer's archiveHint says: done as archivable, off never, reviewed only once recommended.
  assert.ok(p.offered(row([done], false), "done"));
  assert.ok(!p.offered(row([done], false), "off"));
  assert.ok(!p.offered(row([done], false), "reviewed"));
  assert.ok(p.offered(reviewed, "reviewed"));
  assert.ok(!p.offered(kept, "done"));
  const merged = agent({ declared: "final", ending: "all_done", need: "已合并所有代码", outcome: "completed" }, "warm");
  assert.equal(merged.statusText, "已完成：已合并所有代码");
  assert.equal(p.rowStateText(row([merged], false)), "已完成：已合并所有代码");
  assert.ok(!p.settled(row([done], true)));
  // Ended read or not (settled only once read); not while an agent asks, works or there is none.
  assert.ok(p.ended(row([done], true)));
  assert.ok(!p.ended(row([done, helped], false)));
  assert.ok(!p.ended(row([done, works], false)));
  assert.ok(!p.ended(row([], false)));
  assert.ok(!p.settled(row([done, helped], false)));
  assert.equal(p.rowStateText(row([done, helped], false)), "需要你处理：要 key");
  assert.equal(p.rowStateText(row([done, waits], false)), "等待：CI 跑完");
  assert.equal(p.rowStateText(row([done, works], false)), null);
  assert.ok(!p.settled(row([], false)));
  const card = { seq: 4, card: { type: "text" }, message: { seq: 4, text: "**域名用哪个？**\n细节" } };
  const asked = row([done], false);
  asked.card = card;
  // A line that asks for a decision is about no message: the chat leads to what it asks.
  assert.deepEqual([p.settled(asked), p.rowStateLine(asked)], [false, ["奏 · 域名用哪个？", null, "域名用哪个？", { kind: "decision", text: "奏", rest: " · 域名用哪个？" }]]);
  // A card waiting for the viewer: not ended, its agent's done or not.
  assert.ok(!p.ended(asked));
  asked.agents = [agent(null, "running")];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  asked.agents = [waits];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  asked.agents = [helped];
  assert.deepEqual(p.rowStateLine(asked), ["需要你处理：要 key", null, "要 key", { kind: "need", rest: "要 key" }]);
  asked.agents = [agent({ outcome: "failed", detail: "auth: 401" }, "warm")];
  assert.equal(p.rowStateText(asked), "出错：登录失效");
  asked.agents = [agent({ declared: "block", ending: "need_decision", outcome: "completed" }, "warm")];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  // Let go by the viewer: the row says nothing of it, its agent asking still.
  asked.card.dismissed = true;
  assert.equal(p.rowStateText(asked), null);
  const needing = row([helped], false);
  needing.need = { seq: 9, message: { seq: 9, text: "要 key" }, before: [] };
  assert.equal(p.rowStateText(needing), "需要你处理：要 key");
  needing.need.dismissed = true;
  assert.equal(p.rowStateText(needing), null);
  asked.agents = [done];
  assert.ok(p.settled(asked));
  const about = (a: J) => agent({ declared: "final", ending: "all_done", need: "已合进 main", about: a, outcome: "completed" }, "warm");
  const here = row([about({ thread: 7, seq: 12, ts: "1.2" })], false);
  here.thread = 7;
  assert.deepEqual(p.rowStateLine(here), ["已完成：已合进 main", 12, "已完成：已合进 main", { kind: "done", rest: "已合进 main" }]);
  here.agents = [about({ thread: 8, seq: 12, ts: "1.2" })];
  assert.deepEqual(p.rowStateLine(here), ["已完成：已合进 main", null, "已完成：已合进 main", { kind: "done", rest: "已合进 main" }]);
  const waiting = row([agent({ declared: "waiting", ending: "waiting", waitFor: "CI", about: { thread: 7, seq: 3, ts: "1.1" }, outcome: "completed", endedAt: 5 }, "warm")], false);
  waiting.thread = 7;
  assert.deepEqual(p.rowStateLine(waiting), ["等待：CI", 3, "等待：CI", { kind: "wait", rest: "CI" }]);
  // What leads a session's words is said with them (not read back out of them): done alone, a need, watching whole.
  assert.deepEqual([done.statusText, done.statusLead, done.statusRest], ["已完成", "done", ""]);
  assert.deepEqual([helped.statusLead, helped.statusRest], ["need", "要 key"]);
  assert.deepEqual([waits.statusText, waits.statusLead, waits.statusRest], ["等待：CI 跑完", "wait", "CI 跑完"]);
  assert.deepEqual([works.statusLead, works.statusRest], [undefined, undefined]);
  const failed = agent({ outcome: "failed", detail: "auth: 401" }, "warm");
  assert.deepEqual([failed.statusText, failed.statusLead], ["出错：登录失效", undefined]);
  const watching = p.session({ key: "w", process: "warm", pending: 0, lastTurn: { declared: "waiting", ending: "waiting", outcome: "completed", endedAt: 5 }, watch: { every: 60 } });
  assert.deepEqual([watching.statusText, watching.statusLead, watching.statusRest], ["监控中", "watch", "监控中"]);
});

test("what_a_profile_runs_what_can_be_taken_off_and_which_machine_logins_are_offered", () => {
  // all it runs (the station's: those named, then the rest its check found); of those named, the one its provider does
  // not list can be taken off
  let q: J = { models: ["mine", "b", "a"], named: ["mine", "b"], check: { models: ["a", "b"] } };
  q = p.profile(q);
  assert.deepEqual(q.available, ["mine", "b", "a"]);
  assert.deepEqual(q.added, ["mine"]);
  assert.equal(q.modelsText, "3 个模型");
  const c = { now: 0, offsetMin: 0 };
  let o: J = {
    profiles: [{ runtime: "claude", machine: true, models: [] }],
    machineLogins: [
      { runtime: "claude", loggedIn: true, plan: "max" },
      { runtime: "codex", loggedIn: true, plan: "plus" },
      { runtime: "codex", loggedIn: true, plan: null },
      { runtime: "codex", loggedIn: true, plan: "unknown" },
      { runtime: "codex", loggedIn: false, plan: "plus" },
      { runtime: "codex", loggedIn: false, plan: "prolite" },
      { runtime: "codex", loggedIn: false, plan: "pro" },
      { runtime: "codex", loggedIn: false, plan: "promax" },
      { runtime: "codex", loggedIn: false, plan: "free_workspace" },
    ],
  };
  o = p.decorate({ topic: "overview", station: "w/s" }, o, c);
  assert.deepEqual(o.machineLogins.map((l: J) => l.offered === true), [false, true, false, false, false, false, false, false, false]);
  // its plan as its vendor names it, for its tag (the web's and the apps' alike)
  assert.deepEqual(o.machineLogins.map((l: J) => l.planText), ["Max", "Plus", "", "", "Plus", "Pro 100", "Pro 200", "Pro 500", "Free Workspace"]);
});

test("a_stations_profiles_come_by_kind_of_account_those_in_trouble_first_in_each", () => {
  const sub = (id: string, runtime: string, extra: J = {}) => ({ id, runtime, access: { kind: "subscription" }, ...extra });
  let o: J = {
    profiles: [
      { id: "key", runtime: "claude", access: { kind: "anthropic-api" } },
      sub("gpt", "codex"),
      sub("super", "grok"),
      sub("cur", "cursor"),
      sub("dev", "devin"),
      sub("claude-ok", "claude"),
      { id: "key-failed", runtime: "codex", access: { kind: "env" }, check: { state: "failed", detail: "timeout" } },
      sub("claude-failed", "claude", { check: { state: "failed", detail: "timeout" } }),
    ],
  };
  o = p.decorate({ topic: "overview", station: "w/s" }, o, { now: 0, offsetMin: 0 });
  assert.deepEqual(o.profiles.map((q: J) => [q.group, q.groupTitle, q.id]), [
    ["claude", "Claude 订阅", "claude-failed"],
    ["claude", "Claude 订阅", "claude-ok"],
    ["chatgpt", "ChatGPT 订阅", "gpt"],
    ["grok", "SuperGrok 订阅", "super"],
    ["cursor", "Cursor 订阅", "cur"],
    ["devin", "Devin 订阅", "dev"],
    ["key", "API Key", "key-failed"],
    ["key", "API Key", "key"],
  ]);
});

test("bound_subscriptions_hide_only_the_same_machine_account", () => {
  let o: J = {
    profiles: [
      { name: "Renamed", runtime: "claude", access: { kind: "subscription" }, email: " A@x.com " },
      { runtime: "codex", access: { kind: "env" }, email: "b@x.com" },
      { runtime: "codex", access: { kind: "subscription" }, email: "c@x.com" },
      { name: "d@x.com", runtime: "codex", access: { kind: "subscription" } },
    ],
    machineLogins: [
      { runtime: "claude", email: "a@x.com" },
      { runtime: "codex", email: "a@x.com" },
      { runtime: "codex", email: "b@x.com" },
      { runtime: "codex", email: "c@x.com" },
      { runtime: "codex", email: "d@x.com" },
      { runtime: "claude", email: "" },
      { runtime: "claude" },
    ],
  };
  for (const l of o.machineLogins) Object.assign(l, { loggedIn: true, plan: "pro" });
  const topic = { topic: "overview", station: "w/s" };
  const clock = { now: 0, offsetMin: 0 };
  o = p.decorate(topic, o, clock);
  assert.deepEqual(o.machineLogins.map((l: J) => l.offered === true), [false, true, true, false, true, true, true]);
  o.profiles = [];
  o = p.decorate(topic, o, clock);
  assert.ok(o.machineLogins.every((l: J) => l.offered === true));
});

test("how_a_station_archives_on_its_own_is_said_and_offered_by_the_core", () => {
  const topic = { topic: "overview", station: "w/s" };
  const c = { now: 0, offsetMin: 0 };
  const shown = (archiving: J): J => (p.decorate(topic, { archiving }, c) as J).archiving;
  const off = shown({ days: 0, slackDays: 3, reviewed: true, canEdit: true });
  assert.deepEqual([off.mode, off.summaryText], ["off", "不自动归档 · Slack：3 天"]);
  assert.deepEqual([off.daysOffered, off.slackDaysOffered], [[1, 3, 7, 30], [0, 3, 7, 30]]);
  const idle = shown({ days: 1, slackDays: 0, reviewed: false, canEdit: false });
  assert.deepEqual([idle.mode, idle.summaryText], ["idle", "空闲就归档 · 1 天 · Slack：不归档"]);
  // The days kept are offered among the others, in order, when they are none of them.
  const reviewed = shown({ days: 14, slackDays: 60, reviewed: true, canEdit: true });
  assert.deepEqual([reviewed.mode, reviewed.summaryText], ["reviewed", "按模型判断 · 14 天 · Slack：60 天"]);
  assert.deepEqual([reviewed.daysOffered, reviewed.slackDaysOffered], [[1, 3, 7, 14, 30], [0, 3, 7, 30, 60]]);
  assert.ok("ok" in conform("ArchivingView", reviewed), JSON.stringify(conform("ArchivingView", reviewed)));
  // A station from before it: none.
  assert.equal("archiving" in (p.decorate(topic, { counts: {} }, c) as J), false);
});

test("what_the_clients_show_is_put_in_here", () => {
  const c = { now: 1_790_467_200_000, offsetMin: 480 };
  let s: J = { runtime: "codex", model: "gpt-6-astra", effort: "medium", process: "warm", lastTurn: { declared: "block" }, firstText: "<@U1> 看看 CI" };
  s = p.session(s);
  assert.deepEqual([s.statusText, s.tone, s.badgeText], ["需要你处理", "blue", "agent 已暂停，等待处理"]);
  assert.deepEqual([s.titleText, s.agentText, s.maker.id], ["看看 CI", "GPT-6 Astra · medium", "openai"]);
  assert.equal(s.modelName, "GPT-6 Astra");
  assert.deepEqual([s.processText, s.efforts[0]], ["保温中", "minimal"]);
  let v: J = {
    createdAt: c.now - 180_000,
    quota: {
      windows: [
        { label: "每周", usedPercent: 95, resetsAt: c.now + 3_900_000 },
        { label: "5 小时", usedPercent: 10, resetsAt: null },
      ],
    },
  };
  v = p.times(v, c);
  assert.equal(v.time.createdAt.ago, "3 分钟前");
  const w = v.quota.windows;
  assert.deepEqual([w[0].mark, w[1].mark, w[1].level, w[1].refills], ["5H", "W", "red", "1 小时 5 分钟后刷新"]);
  const members = [{ email: "a@x.com", name: "阿一", picture: "https://p/a" }];
  assert.equal(p.mentions("<@UBOT> 和 <@U9> 看下", [["UBOT", "ds-ember"]], members), "@ds-ember 和 @U9 看下");
  assert.equal(p.mentions("<@UBOT> 和 <@U9> 看下", [["UBOT", "ds-ember"], ["U9", "Mia"]], members), "@ds-ember 和 @Mia 看下");
  let me: J = { id: "a@x.com", email: "a@x.com", name: "A" };
  me = p.person(me, { id: "a@x.com", email: "a@x.com" }, members);
  assert.deepEqual(me.shown, { name: "阿一", display: "你", picture: "https://p/a", mine: true });
  const fromSlack = p.person({ id: "slack:c:U1", name: "A", email: "a@x.com", via: "slack", picture: "https://avatars.slack-edge.com/a_72.png" }, me, members);
  assert.equal(fromSlack.shown.picture, "https://avatars.slack-edge.com/a_72.png", "a Slack person's own picture, over their account's");
  let h: J = {
    hostname: "studio", os: "macOS 26", arch: "arm64", cpus: 8, load: 0.5, uptimeSec: 90_000,
    memory: { usedBytes: 8 * GIB, totalBytes: 32 * GIB, swapUsedBytes: null },
    disk: { totalBytes: 1000 * GIB, freeBytes: 50 * GIB }, emberRssBytes: 100 * 1024 ** 2,
  };
  h = p.host(h);
  assert.ok(Number.isInteger(h.meters[0].percent) && Number.isInteger(v.quota.windows[0].left));
  assert.deepEqual([h.summary, h.facts[3]], ["8 核 · 32 GB", "已运行 1 天 1 小时"]);
  assert.deepEqual([h.meters[0].label, h.meters[0].value], ["CPU 负载", "50%"]);
  h.cpuBusy = 0.93;
  h.cpuModel = "Apple M2 Max";
  h = p.host(h);
  const cpu = h.meters[0];
  assert.deepEqual([cpu.label, cpu.percent, cpu.level, cpu.value, cpu.note], ["CPU", 93, "red", "93%", "负载 4.0 · Apple M2 Max"]);
  assert.deepEqual([h.meters[2].level, h.meters[2].value, h.emberText], ["red", "剩余 50.0 GB / 1000 GB", "still.fail 100 MB"]);
  assert.match(h.usage, /^内存 .+ · 磁盘 剩余 50\.0 GB \/ 1000 GB$/);
  assert.equal(h.identity, "Apple M2 Max · 32 GB · macOS 26");
  assert.deepEqual(h.details.map((d: J) => `${d.label} ${d.value}`), ["主机名 studio", "芯片 Apple M2 Max · 8 核 · arm64", "已运行 1 天 1 小时", "still.fail 进程占用 100 MB"]);
  assert.deepEqual([cpu.left, cpu.remaining, cpu.big, cpu.unit, cpu.title, cpu.total], [7, "空闲 7%", "7", "%", "CPU 空闲", "负载 4.0"]);
  const left = h.meters[2];
  assert.deepEqual([left.left, left.big, left.unit, left.title, left.total], [5, "50.0", "GB", "磁盘剩", "共 1000 GB"]);
});

test("a_watching_chat_says_what_it_watches_and_what_archiving_it_means", () => {
  const agent = (watch: J) => ({ key: "a", watch });
  assert.equal(p.rowWatch([{ key: "a" }]), null);
  const marked = p.rowWatch([agent({ names: ["盯 CI"], since: 0, at: 1 }), { key: "b" }, agent({ names: ["relay 延迟"], since: 0, at: 0 })]);
  assert.deepEqual(marked, { text: "监控中：盯 CI、relay 延迟", ask: "「盯 CI」、「relay 延迟」仍在监控。归档会停止监控。" });
});

test("a_meter_is_drawn_as_an_allowance_to_what_is_left", () => {
  let h: J = { memory: { usedBytes: 5.3 * GIB, totalBytes: 6 * GIB }, disk: { freeBytes: 6 * GIB, totalBytes: 60 * GIB } };
  h = p.host(h);
  assert.equal(h.meters[1].remaining, "剩 0.7 G");
  assert.deepEqual([h.meters[1].percent, h.meters[1].left], [88, 12]);
  assert.equal(h.meters[2].remaining, "剩 6.0 G");
  assert.equal(h.meters[2].percent, 90);
  h.memory.usedBytes = 7 * GIB;
  h = p.host(h);
  assert.equal(h.meters[1].remaining, "剩 0.0 G");
});

test("loss_is_counted_on_the_way_in_use_and_not_across_a_change_of_it", () => {
  const way = (path: string, sent: number, lost: number) => ({ path, sent, lost });
  assert.deepEqual(packetsSince(way("1", 100, 2), way("1", 160, 3)), { sent: 60, lost: 1 });
  // Another way now, or a new connection counting from nothing: its counts say nothing about the last sample's.
  assert.deepEqual(packetsSince(way("1", 100, 2), way("3", 400, 40)), { sent: 0, lost: 0 });
  assert.deepEqual(packetsSince(way("0", 100, 2), way("0", 10, 0)), { sent: 0, lost: 0 });
  assert.deepEqual(packetsSince(null, way("0", 10, 0)), { sent: 0, lost: 0 });
});

test("a_mac_stations_grants_are_said_in_words_with_what_goes_without_them_and_how_one_is_given", () => {
  const c = { now: 0, offsetMin: 0 };
  const topic = { topic: "overview", station: "w/s" };
  const raw = (screen: boolean, asking: string[], request = true): J => ({
    permissions: {
      grants: [
        { grant: "capture", state: "granted" }, { grant: "control", state: screen ? "granted" : "unknown" }, { grant: "documents", state: "granted" },
        { grant: "desktop", state: "unknown" }, { grant: "downloads", state: "denied" }, { grant: "camera", state: "unknown" },
      ],
      asking, screen, request,
    },
  });
  // The screen drivable: its page to open once one is asked for; what is missing said in a line.
  let o: J = p.decorate(topic, raw(true, []), c);
  assert.deepEqual(o.permissions.grants.map((g: J) => [g.id, g.name, g.granted, g.asking]), [
    ["capture", "屏幕录制", true, false], ["control", "辅助功能", true, false], ["documents", "文稿", true, false],
    ["desktop", "桌面", false, false], ["downloads", "下载", false, false],
  ]);
  assert.equal(o.permissions.grants[0].line, "远程查看此屏幕，agent 截屏");
  assert.equal(o.permissions.note, "当前不可用：访问桌面、访问下载");
  assert.equal(o.permissions.screen, "/w/w/s/s/screen/desktop");
  assert.equal(o.permissions.canRequest, true);
  // The window up for Desktop: how it is given (through the screen).
  o = p.decorate(topic, raw(true, ["desktop"]), c);
  assert.deepEqual([o.permissions.grants[3].asking, o.permissions.grants[3].line], [true, "授权窗口已在该 Mac 上打开，可在远程屏幕中点击「允许」"]);
  // Not drivable: no page to open, the person goes to the Mac; a read-only member may not ask.
  o = p.decorate(topic, raw(false, ["control"], false), c);
  assert.equal(o.permissions.screen, undefined);
  assert.equal(o.permissions.grants[1].line, "授权窗口已在该 Mac 上打开，请在该 Mac 上点击「允许」");
  assert.equal(o.permissions.note, "当前不可用：远程控制屏幕、访问桌面、访问下载");
  assert.equal(o.permissions.canRequest, false);
  // Local Network not had: where it is switched on, for the app the station runs in.
  o = p.decorate(topic, { permissions: { grants: [{ grant: "localNetwork", state: "denied" }], asking: [], screen: false, request: true, localNetworkName: "youdid.wtf" } }, c);
  assert.deepEqual([o.permissions.grants[0].name, o.permissions.grants[0].line], ["本地网络", "在 系统设置 › 隐私与安全性 › 本地网络 里打开 youdid.wtf，再重启它"]);
  assert.equal(o.permissions.note, "当前不可用：局域网直连");
  o = p.decorate(topic, { permissions: { grants: [{ grant: "localNetwork", state: "granted" }], asking: [], screen: false, request: true, localNetworkName: "youdid.wtf" } }, c);
  assert.equal(o.permissions.grants[0].line, "同一局域网的设备直接连它");
  // All granted: nothing unavailable.
  o = p.decorate(topic, { permissions: { grants: [{ grant: "capture", state: "granted" }], asking: [], screen: true, request: true } }, c);
  assert.equal(o.permissions.note, undefined);
  // Not a Mac, or a station from before them: none.
  assert.equal("permissions" in (p.decorate(topic, { counts: {} }, c) as J), false);
  assert.equal("permissions" in (p.decorate(topic, { permissions: "?" }, c) as J), false);
  const shown = p.decorate(topic, raw(true, ["desktop"]), c) as J;
  assert.ok("ok" in conform("StationPermissions", shown.permissions), JSON.stringify(conform("StationPermissions", shown.permissions)));
});

test("a_windows_stations_running_as_administrator_is_said_with_how_a_change_goes_and_how_it_failed", () => {
  const c = { now: 0, offsetMin: 0 };
  const topic = { topic: "overview", station: "w/s" };
  const shown = (elevation: J): J => (p.decorate(topic, { elevation }, c) as J).elevation;
  const base = { on: false, elevated: false, canElevate: true, manage: true };
  let o = shown(base);
  assert.deepEqual(o, { on: false, busy: false, line: "agent 的命令都以管理员权限运行，不再弹 UAC；没有逐条批准，station 由整个 workspace 共用", canChange: true });
  assert.ok("ok" in conform("StationElevation", o), JSON.stringify(conform("StationElevation", o)));
  // Windows' prompt up: the switch where it goes, waiting; who must answer it, and that nothing is lost if nobody does.
  o = shown({ ...base, step: "asking", want: true });
  assert.deepEqual([o.on, o.busy, o.canChange], [true, true, false]);
  assert.match(o.line, /需要有人在这台电脑前点「是」.*station 不受影响/);
  assert.match(shown({ ...base, on: true, elevated: true, step: "restarting", want: false }).line, /^正在重启 station/);
  // Failed: nothing changed, said why; an error with its words.
  o = shown({ ...base, failed: "unanswered", want: true });
  assert.deepEqual([o.on, o.busy, o.canChange], [false, false, true]);
  assert.match(o.failed, /^2 分钟内没人确认 UAC/);
  assert.equal(shown({ ...base, failed: "error", message: "拒绝访问" }).failed, "切换失败，设置没有改变：拒绝访问");
  assert.equal(shown({ ...base, failed: "declined" }).failed, "UAC 被拒绝，设置没有改变");
  // Its user no administrator, or a member not its managers: not switched from here.
  assert.deepEqual([shown({ ...base, canElevate: false }).canChange, shown({ ...base, canElevate: false }).line], [false, "运行 station 的 Windows 账号不是管理员，不能以管理员身份运行"]);
  assert.equal(shown({ ...base, manage: false }).canChange, false);
  // Not Windows, or a station from before it: none.
  assert.equal("elevation" in (p.decorate(topic, { counts: {} }, c) as J), false);
});

test("a_connect_says_where_it_is_reached_how_it_runs_and_what_switching_it_does", () => {
  const base: J = { id: "f1", name: "助手", kind: "feishu", mode: "single-session", requireMention: true, session: "s1", feishu: { appId: "cli_1", domain: "lark" }, bind: { runtime: "claude" } };
  const c = p.connect(base);
  // a Feishu connect: its groups' words, its platform where no Slack workspace is said
  assert.equal(c.placeText, "Lark");
  assert.equal(c.modeLabel, "所有群共用一个会话");
  assert.ok(c.modeSentence.endsWith("仅在被 @ 时唤醒。"));
  assert.equal(c.modeWords.single.label, "所有群共用一个会话");
  assert.equal(p.connect({ ...base, kind: "slack", team: "Acme", feishu: undefined }).placeText, "Acme");
  // switched to one each, with two running: what that does in its groups' words, then that the running finish
  const changes = p.modeChanges(base, 2);
  const multi = changes.find((x: J) => x.mode === "multi-session");
  assert.deepEqual([multi.changed, multi.action], [true, "改为多会话"]);
  assert.deepEqual(multi.effects, [
    "当前绑定的会话将不再接收新消息。此后每个群被 @ 时各开启一个会话。",
    "如需在群里继续，须重新 @，这将开启一个新会话，不含之前的上下文。",
    "以后切回单会话时，将继续使用原来的会话。",
    "当前有 2 个会话正在运行，它们会完成当前这一轮。",
  ]);
  // the way it is now changes nothing, so says nothing; answering every message is said on its own
  const same = changes.find((x: J) => x.mode === "single-session" && x.requireMention);
  assert.deepEqual([same.changed, same.effects, same.action], [false, [], "确认更改"]);
  const all = changes.find((x: J) => x.mode === "single-session" && !x.requireMention);
  assert.equal(all.effects[0], "无需 @：它所在的所有群和私聊中的每条消息都会发送给 agent，用量会明显增加。");
});

test("a_slack_apps_permissions_are_said_in_sections_those_only_admins_allow_marked", () => {
  const sections = p.slackSections();
  assert.deepEqual(sections.map((s: J) => s.title)[0], "消息");
  assert.deepEqual(sections.flatMap((s: J) => s.groups.map((g: J) => g.id)).length, 16);
  const base = sections[0].groups[0];
  assert.deepEqual([base.id, base.fixed, base.admin], ["base", true, null]);
  const connect = sections[1].groups.find((g: J) => g.id === "connect");
  assert.equal(connect.tip, `${connect.description} ${connect.admin}`);
});
