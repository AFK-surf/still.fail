// The Rust core's present.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { holdLanguage } from "../src/i18n.ts";
import * as p from "../src/present.ts";

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

  const relay: J = { path: "relay", relay: "relay.still.fail", rttMs: 286, rxBytes: 0, txBytes: 0, samples: [sample(1200, 40, 2)] };
  shown = p.net(relay, unnamed);
  assert.equal(shown.path, "中继 relay.still.fail");
  const named = (host: string) => (host === "relay.still.fail" ? "北京" : null);
  assert.equal(p.net(relay, named).path, "北京中继");
  assert.equal(shown.rtt.level, "ok");
  assert.deepEqual(shown.loss, { text: "丢包 5.0%", level: "amber" });
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
  assert.deepEqual([shown.path, shown.down], ["正在选路", "—"]);
  assert.deepEqual(shown.rtt, { text: "1.5 s", level: "red" });
});

test("a_rows_people_are_said_in_words_who_started_it_first", () => {
  const me = { id: "me@x.com", email: "me@x.com" };
  let row: J = { creator: { id: "wang@x.com", name: "小王" }, people: [{ id: "lina@x.com", name: "Lina" }, { id: "me@x.com", name: "Me" }] };
  p.rowPeople(row, me, [], []);
  assert.equal(row.peopleText, "小王 发起 · Lina、你");
  row = { people: [{ id: "lina@x.com", name: "Lina" }] };
  p.rowPeople(row, me, [], []);
  assert.equal(row.peopleText, "Lina");
});

test("profile_recovery_follows_states_and_clears_after_success", () => {
  const q: J = { access: { kind: "subscription" }, check: { state: "login" }, quota: { state: "unavailable" } };
  p.profile(q);
  assert.equal(q.trouble.action, "login");
  q.machine = true;
  p.profile(q);
  assert.equal(q.trouble.action, "command");
  q.check.state = "ok";
  p.profile(q);
  assert.equal(q.trouble.action, "quota");
  assert.equal(q.checkText, "可用");
  assert.equal(q.trouble.detail, "暂时查不到额度");
  q.quota.state = "ok";
  p.profile(q);
  assert.equal(q.trouble, null);
  q.quota.state = "blocked";
  p.profile(q);
  assert.equal(q.trouble.title, "账号被停用");
  assert.equal(q.checkTone, "red");
});

test("a_profile_says_what_it_can_do_from_where_its_provider_speaks", () => {
  const text = (q: J) => {
    p.profile(q);
    return [q.access?.kind ?? "", q.usesText ?? ""];
  };
  assert.deepEqual(text({ runtimes: [], access: { kind: "env", provider: "deepseek" } }), ["api-provider", "自动决策"]);
  assert.deepEqual(text({ runtimes: ["claude"], access: { kind: "api-provider", provider: "openrouter" } }), ["api-provider", "Claude Code · 自动决策"]);
  assert.equal(text({ runtimes: ["codex"], access: { kind: "api-provider", provider: "azure-openai", endpoint: "https://x.openai.azure.com/openai/v1" } })[1], "Codex");
  assert.equal(text({ runtimes: ["claude", "codex"], access: { kind: "opencode-go" } })[1], "Claude Code · Codex · 自动决策");
  assert.equal(text({ runtimes: ["claude"], access: { kind: "anthropic-api" } })[1], "Claude Code");
  assert.deepEqual(text({ runtimes: ["codex"], access: { kind: "env" } }), ["env", ""]);
  assert.equal(text({ runtimes: ["codex"], access: { kind: "env" }, check: { decision: { state: "ready" } } })[1], "Codex · 自动决策");
  const canName = (provider: string) => {
    const q: J = { runtimes: [], access: { kind: "env", provider } };
    p.profile(q);
    return q.canAddModel === true;
  };
  assert.ok(!canName("jev") && canName("minimax") && canName("deepseek"));
  const jev: J = { runtimes: [], access: { kind: "env", provider: "jev" }, check: { state: "ok", decision: { state: "ready", detail: "已识别 1 个决策模型", models: ["jev-latest"] } } };
  p.profile(jev);
  assert.deepEqual([jev.decisionOnly, jev.decisionModels, jev.decisionText], [true, ["jev-latest"], "已识别 1 个决策模型"]);
  const waiting: J = { runtimes: [], access: { kind: "env", provider: "jev" }, check: { state: "ok" } };
  p.profile(waiting);
  assert.deepEqual([waiting.decisionModels, waiting.decisionText], [[], "正在识别决策模型…"]);
  const x: J = { runtimes: [], access: { kind: "env", provider: "xiaomi" }, check: { state: "failed" } };
  p.profile(x);
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
  const waits = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600 } };
  assert.deepEqual(p.waiting(waits), { since: 5, seconds: 600, text: "等待中" });
  assert.deepEqual(p.waiting({ process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5 } }), { since: 5, seconds: null, text: "等待中" });
  assert.equal(p.waiting({ process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitFor: "CI 跑完" } }).text, "在等：CI 跑完");
  const watching: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600 }, watch: { names: ["盯 CI"], since: 1, at: 5 } };
  p.session(watching);
  assert.deepEqual([watching.statusText, watching.mark], ["监控中", null]);
  const plain: J = structuredClone(waits);
  p.session(plain);
  assert.equal(plain.statusText, "等待中");
  const said: J = { process: "warm", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5, waitSeconds: 600, waitFor: "CI 跑完" } };
  p.session(said);
  assert.equal(said.statusText, "在等：CI 跑完");
  assert.equal(p.waiting({ process: "running", lastTurn: { declared: "waiting", outcome: "completed", endedAt: 5 } }), null);
  assert.equal(p.waiting({ process: "warm", pending: 1, lastTurn: { declared: "waiting", endedAt: 5 } }), null);
  assert.equal(st({}), "idle");
});

test("an_account_its_provider_refuses_says_so_whatever_its_check_found", () => {
  const q: J = { check: { state: "ok" }, quota: { state: "blocked", windows: [] } };
  p.profile(q);
  assert.deepEqual([q.checkText, q.checkTone], ["被停用", "red"]);
  const ok: J = { check: { state: "ok" }, quota: { state: "unavailable", windows: [] } };
  p.profile(ok);
  assert.equal(ok.checkText, "可用");
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
});

test("a_profiles_models_come_by_series", () => {
  const q: J = { models: ["claude-opus-5-5"], check: { models: ["claude-sonnet-5", "claude-opus-4-8", "claude-opus-5-5", "my-model", "claude-fable-5-1"] } };
  p.profile(q);
  assert.deepEqual(q.series, [
    { name: "Fable", models: ["claude-fable-5-1"] },
    { name: "Opus", models: ["claude-opus-5-5", "claude-opus-4-8"] },
    { name: "Sonnet", models: ["claude-sonnet-5"] },
    { name: "其他", models: ["my-model"] },
  ]);
});

test("how_a_turn_ended_says_itself_in_words", () => {
  const words = (turn: J) => {
    const s: J = { process: "warm", lastTurn: turn };
    p.session(s);
    return s.statusText;
  };
  assert.equal(words({ declared: "final", ending: "all_done", outcome: "completed" }), "做完了");
  assert.equal(words({ declared: "block", ending: "need_help", need: "要 Stripe 的测试 key", outcome: "completed" }), "要你帮忙：要 Stripe 的测试 key");
  assert.equal(words({ declared: "block", outcome: "completed" }), "要你帮忙");
  assert.equal(words({ declared: "block", ending: "need_decision", outcome: "completed" }), "要你帮忙");
  assert.equal(words({ outcome: "failed", detail: "rate_limit: You've hit your limit" }), "出问题：额度用完");
  assert.equal(words({ outcome: "failed", detail: "auth: 401" }), "出问题：登录失效");
  assert.equal(words({ outcome: "aborted" }), "出问题：被停止");
  assert.equal(words({ outcome: "completed" }), "出问题：没说一声就停了");
  const decided: J = { process: "warm", lastTurn: { declared: "block", ending: "need_decision", outcome: "completed" } };
  p.session(decided);
  assert.equal(decided.mark, "block");
});

test("a_decision_agent_passes_the_chat_shape", () => {
  const s: J = { key: "ember:c-decision", runtime: "codex", process: "warm", pending: 0, lastTurn: { kind: "message", startedAt: 1, declared: "block", ending: "need_decision", outcome: "completed" } };
  p.session(s);
  const agent = { status: p.shownStatus(s), badge: p.markOf(s), session: s, profiles: [], choices: [], attention: [], turns: [], threads: [], jobs: [] };
  const checked = conform("ChatAgent", agent) as J;
  assert.ok("ok" in checked, JSON.stringify(checked));
  assert.equal(checked.ok.status, "block");
  assert.equal(checked.ok.badge, "block");
  assert.equal(checked.ok.session.statusText, "要你帮忙");
  const legacy = { ...checked.ok, status: "decision" };
  assert.equal((conform("ChatAgent", legacy) as J).ok.status, "decision");
});

test("a_chat_with_nothing_left_is_settled_and_says_where_it_stands", () => {
  const agent = (turn: J, process: string): J => {
    const a: J = { key: "k", process, pending: 0, lastTurn: turn };
    p.session(a);
    return a;
  };
  const done = agent({ declared: "final", ending: "all_done", outcome: "completed" }, "warm");
  const helped = agent({ declared: "block", ending: "need_help", need: "要 key", outcome: "completed" }, "warm");
  const waits = agent({ declared: "waiting", ending: "waiting", waitFor: "CI 跑完", outcome: "completed", endedAt: 5 }, "warm");
  const works = agent(null, "running");
  const row = (agents: J[], unread: boolean): J => ({ agents: structuredClone(agents), unread });
  assert.ok(p.settled(row([done], false)));
  const kept = row([done], false);
  kept.pinned = 1700000000000;
  assert.ok(p.pinned(kept));
  assert.ok(!p.pinned(row([done], false)));
  assert.equal(p.rowStateText(row([done], false)), "做完了");
  const recommended = row([done], false);
  recommended.archiveRecommended = true;
  assert.equal(p.rowStateText(recommended), "推荐归档 · 做完了");
  recommended.archiveReminderDismissed = true;
  assert.equal(p.rowStateText(recommended), "做完了");
  // Where the station's archive review is on, a done chat is offered for the archive only once it recommended so.
  assert.ok(p.archivable(row([done], false)));
  const reviewed = row([done], false);
  reviewed.archiveReviewed = true;
  assert.ok(!p.archivable(reviewed));
  reviewed.archiveRecommended = true;
  assert.ok(p.archivable(reviewed));
  assert.ok(!p.archivable(kept));
  const merged = agent({ declared: "final", ending: "all_done", need: "已合并所有代码", outcome: "completed" }, "warm");
  assert.equal(merged.statusText, "做完了：已合并所有代码");
  assert.equal(p.rowStateText(row([merged], false)), "做完了：已合并所有代码");
  assert.ok(!p.settled(row([done], true)));
  assert.ok(!p.settled(row([done, helped], false)));
  assert.equal(p.rowStateText(row([done, helped], false)), "要你帮忙：要 key");
  assert.equal(p.rowStateText(row([done, waits], false)), "在等：CI 跑完");
  assert.equal(p.rowStateText(row([done, works], false)), null);
  assert.ok(!p.settled(row([], false)));
  const card = { seq: 4, card: { type: "text" }, message: { seq: 4, text: "**域名用哪个？**\n细节" } };
  const asked = row([done], false);
  asked.card = card;
  assert.deepEqual([p.settled(asked), p.rowStateLine(asked)], [false, ["奏 · 域名用哪个？", 4]]);
  asked.agents = [agent(null, "running")];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  asked.agents = [waits];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  asked.agents = [helped];
  assert.deepEqual(p.rowStateLine(asked), ["要你帮忙：要 key", 4]);
  asked.agents = [agent({ outcome: "failed", detail: "auth: 401" }, "warm")];
  assert.equal(p.rowStateText(asked), "出问题：登录失效");
  asked.agents = [agent({ declared: "block", ending: "need_decision", outcome: "completed" }, "warm")];
  assert.equal(p.rowStateText(asked), "奏 · 域名用哪个？");
  asked.card.dismissed = true;
  assert.equal(p.rowStateText(asked), "要你帮忙");
  asked.agents = [done];
  assert.ok(p.settled(asked));
  const about = (a: J) => agent({ declared: "final", ending: "all_done", need: "已合进 main", about: a, outcome: "completed" }, "warm");
  const here = row([about({ thread: 7, seq: 12, ts: "1.2" })], false);
  here.thread = 7;
  assert.deepEqual(p.rowStateLine(here), ["做完了：已合进 main", 12]);
  here.agents = [about({ thread: 8, seq: 12, ts: "1.2" })];
  assert.deepEqual(p.rowStateLine(here), ["做完了：已合进 main", null]);
  const waiting = row([agent({ declared: "waiting", ending: "waiting", waitFor: "CI", about: { thread: 7, seq: 3, ts: "1.1" }, outcome: "completed", endedAt: 5 }, "warm")], false);
  waiting.thread = 7;
  assert.deepEqual(p.rowStateLine(waiting), ["在等：CI", 3]);
});

test("what_a_profile_can_enable_and_which_machine_logins_are_offered", () => {
  const q: J = { models: ["mine", "b"], check: { models: ["a", "b"] } };
  p.profile(q);
  assert.deepEqual(q.available, ["a", "b", "mine"]);
  const c = { now: 0, offsetMin: 0 };
  const o: J = {
    profiles: [{ runtime: "claude", machine: true, models: [] }],
    machineLogins: [
      { runtime: "claude", loggedIn: true, plan: "max" },
      { runtime: "codex", loggedIn: true, plan: "plus" },
      { runtime: "codex", loggedIn: true, plan: null },
      { runtime: "codex", loggedIn: false, plan: "plus" },
    ],
  };
  p.decorate({ topic: "overview", station: "w/s" }, o, c);
  assert.deepEqual(o.machineLogins.map((l: J) => l.offered === true), [false, true, false, false]);
});

test("bound_subscriptions_hide_only_the_same_machine_account", () => {
  const o: J = {
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
  p.decorate(topic, o, clock);
  assert.deepEqual(o.machineLogins.map((l: J) => l.offered === true), [false, true, true, false, true, true, true]);
  o.profiles = [];
  p.decorate(topic, o, clock);
  assert.ok(o.machineLogins.every((l: J) => l.offered === true));
});

test("what_the_clients_show_is_put_in_here", () => {
  const c = { now: 1_790_467_200_000, offsetMin: 480 };
  const s: J = { runtime: "codex", model: "gpt-6-astra", effort: "medium", process: "warm", lastTurn: { declared: "block" }, firstText: "<@U1> 看看 CI" };
  p.session(s);
  assert.deepEqual([s.statusText, s.tone, s.badgeText], ["要你帮忙", "blue", "agent 停下来等人处理"]);
  assert.deepEqual([s.titleText, s.agentText, s.maker.id], ["看看 CI", "GPT-6 Astra · medium", "openai"]);
  assert.equal(s.modelName, "GPT-6 Astra");
  assert.deepEqual([s.processText, s.efforts[0]], ["保温中", "minimal"]);
  const v: J = {
    createdAt: c.now - 180_000,
    quota: {
      windows: [
        { label: "每周", usedPercent: 95, resetsAt: c.now + 3_900_000 },
        { label: "5 小时", usedPercent: 10, resetsAt: null },
      ],
    },
  };
  p.times(v, c);
  assert.equal(v.time.createdAt.ago, "3 分钟前");
  const w = v.quota.windows;
  assert.deepEqual([w[0].mark, w[1].mark, w[1].level, w[1].refills], ["5H", "W", "red", "1 小时 5 分钟后刷新"]);
  const members = [{ email: "a@x.com", name: "阿一", picture: "https://p/a" }];
  assert.equal(p.mentions("<@UBOT> 和 <@U9> 看下", [["UBOT", "ds-ember"]], members), "@ds-ember 和 @U9 看下");
  const me: J = { id: "a@x.com", email: "a@x.com", name: "A" };
  p.person(me, { id: "a@x.com", email: "a@x.com" }, members);
  assert.deepEqual(me.shown, { name: "阿一", display: "你", picture: "https://p/a", mine: true });
  const h: J = {
    hostname: "studio", os: "macOS 26", arch: "arm64", cpus: 8, load: 0.5, uptimeSec: 90_000,
    memory: { usedBytes: 8 * GIB, totalBytes: 32 * GIB, swapUsedBytes: null },
    disk: { totalBytes: 1000 * GIB, freeBytes: 50 * GIB }, emberRssBytes: 100 * 1024 ** 2,
  };
  p.host(h);
  assert.ok(Number.isInteger(h.meters[0].percent) && Number.isInteger(v.quota.windows[0].left));
  assert.deepEqual([h.summary, h.facts[3]], ["8 核 · 32 GB", "已运行 1 天 1 小时"]);
  assert.deepEqual([h.meters[0].label, h.meters[0].value], ["CPU 负载", "50%"]);
  h.cpuBusy = 0.93;
  h.cpuModel = "Apple M2 Max";
  p.host(h);
  const cpu = h.meters[0];
  assert.deepEqual([cpu.label, cpu.percent, cpu.level, cpu.value, cpu.note], ["CPU", 93, "red", "93%", "负载 4.0 · Apple M2 Max"]);
  assert.deepEqual([h.meters[2].level, h.meters[2].value, h.emberText], ["red", "剩 50.0 GB / 1000 GB", "still.fail 100 MB"]);
});

test("a_watching_chat_says_what_it_watches_and_what_archiving_it_means", () => {
  const agent = (watch: J) => ({ key: "a", watch });
  assert.equal(p.rowWatch([{ key: "a" }]), null);
  const marked = p.rowWatch([agent({ names: ["盯 CI"], since: 0, at: 1 }), { key: "b" }, agent({ names: ["relay 延迟"], since: 0, at: 0 })]);
  assert.deepEqual(marked, { text: "监控中：盯 CI、relay 延迟", ask: "「盯 CI」、「relay 延迟」还在监控。归档后它照常运行，有新消息时对话会回到列表。" });
});

test("focus_message_results_and_pending_requests", () => {
  for (const ending of ["all_done", "need_human", "need_help", "need_decision"]) assert.ok(p.focusMessage({ authorKind: "agent", ending }));
  assert.ok(p.focusMessage({ authorKind: "agent", declared: "final" }));
  assert.ok(p.focusMessage({ authorKind: "agent", decision: { resolved: false } }));
  for (const message of [
    { authorKind: "person", ending: "all_done" },
    { authorKind: "agent" },
    { authorKind: "agent", ending: "waiting" },
    { authorKind: "agent", ending: "need_human", decision: { resolved: true } },
    { authorKind: "agent", ending: "need_human", decision: { resolved: false, dismissed: true } },
  ])
    assert.ok(!p.focusMessage(message), JSON.stringify(message));
});

test("alert_capacity_is_remaining_while_its_edge_is_used_percent", () => {
  const h: J = { memory: { usedBytes: 5.3 * GIB, totalBytes: 6 * GIB }, disk: { freeBytes: 6 * GIB, totalBytes: 60 * GIB } };
  p.host(h);
  assert.equal(h.meters[1].remaining, "剩余 0.7 G");
  assert.equal(h.meters[1].percent, 88);
  assert.equal(h.meters[2].remaining, "剩余 6.0 G");
  assert.equal(h.meters[2].percent, 90);
  h.memory.usedBytes = 7 * GIB;
  p.host(h);
  assert.equal(h.meters[1].remaining, "剩余 0.0 G");
});
