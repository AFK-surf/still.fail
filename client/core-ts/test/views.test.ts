// The Rust core's views.rs tests, ported: a store whose topics the test sets, the views routed as core.ts does.
import assert from "node:assert/strict";
import { test } from "node:test";
import { CoreError } from "../src/error.ts";
import { Effect } from "effect";
import { Data, holds } from "../src/data.ts";
import { apply as applyOps, type Op } from "../src/delta.ts";
import * as format from "../src/format.ts";
import { holdLanguage } from "../src/i18n.ts";
import { merge } from "../src/entries.ts";
import * as decisions from "../src/decisions.ts";
import { topicKey, type Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { EVICT_AFTER_MS, Store, type Source, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { attention, choices, runnableOn } from "../src/views/models.ts";
import { Views, betaOffered, chatDerive, down, shownMessage } from "../src/views/views.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const DAY_MS = 86_400_000;

const VIEWS = new Set(["chats", "chatSearch", "stations", "connects", "chat", "history", "archive", "workspaceMarks", "decisions", "chatJobs", "longJobs"]);

class Router implements Source {
  views!: Views;
  started: Topic[] = [];
  stopped: Topic[] = [];
  computed = 0;
  /// What the station topics say of a held topic whose read failed while nothing is held (station/topics.ts).
  failed = new Map<string, CoreError>();
  start(topic: Topic): void {
    if (VIEWS.has(topic.topic)) this.views.start(topic);
    else this.started.push(topic);
  }
  stop(topic: Topic): void {
    if (VIEWS.has(topic.topic)) this.views.stop(topic);
    else this.stopped.push(topic);
  }
  compute(topic: Topic): Value | undefined {
    const failed = this.failed.get(topicKey(topic));
    if (failed) return { err: failed };
    if (!VIEWS.has(topic.topic)) return undefined;
    this.computed++;
    return this.views.compute(topic);
  }
}

type Ui = { value: J; error: J; messages: number };
const ui = (): Ui => ({ value: undefined, error: undefined, messages: 0 });

function setup() {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  store.setShaped();
  // What the stations hold is in the account's database (data.ts), as in a core: the test writes it there.
  const data = new Data(host, runner, { owner: () => "s1", derive: chatDerive });
  Effect.runSync(data.open(["s1"]));
  store.setHeld((topic) => data.shared(topic), (topic) => data.release(topic));
  data.onChange((topic) => store.changed(topic));
  const router = new Router();
  const beta = { on: false };
  const views = new Views({
    host,
    runner,
    store,
    data,
    emailOf: (ws) => (ws === "ws" ? "Me@x.com" : null),
    betaOf: (ws) => ws === "ws" && beta.on,
    relayName: () => null,
  });
  router.views = views;
  store.setSource(router);
  const t = {
    host,
    data,
    store,
    router,
    views,
    beta,
    subscribe: (id: number, topic: Topic) => store.subscribe(1, id, topic),
    async readAll(uis: [Ui, number][]) {
      await host.time.pass(100);
      for (const [, message] of host.takeEmitted()) {
        const m = message as J;
        if (m.error?.code === "shape") throw new Error(m.error.message);
        const found = uis.find(([, id]) => id === m.id);
        if (!found) continue;
        const [u] = found;
        if ("value" in m) [u.value, u.error] = [m.value, undefined];
        else if ("delta" in m) u.value = applyOps(u.value, m.delta as Op[]);
        else if ("error" in m) u.error = m.error;
        else continue;
        u.messages++;
      }
    },
    async read(u: Ui, id: number) {
      await t.readAll([[u, id]]);
    },
    set: (topic: Topic, value: unknown) => {
      router.failed.delete(topicKey(topic));
      if (holds(topic)) data.set(topic, value);
      else store.set(topic, { ok: value });
    },
    // A held topic's error shows while nothing is held of it (data.ts): what was held goes first, as the core has it
    // go (a workspace gone, a session removed, a station's rows no longer reached); the station topics say why.
    fail: (topic: Topic, error: CoreError) => {
      if (!holds(topic)) return store.set(topic, { err: error });
      if (topic.topic === "workspace") data.dropWorkspace(topic.workspace as string);
      else if (topic.topic === "session") {
        if (data.hasDetail(topic.station as string, topic.key as string)) data.dropSession(topic.station as string, topic.key as string);
      } else data.retain((s) => s !== topic.station, null);
      router.failed.set(topicKey(topic), error);
      store.invalidate(topic);
    },
    started: () => {
      const s = router.started;
      router.started = [];
      return s;
    },
    stopped: () => {
      const s = router.stopped;
      router.stopped = [];
      return sorted(s);
    },
    nowS: () => host.nowMs() / 1000,
  };
  return t;
}

const workspace = (): Topic => ({ topic: "workspace", workspace: "ws" });
const sessions = (st: string): Topic => ({ topic: "sessions", station: st });
const overview = (st: string): Topic => ({ topic: "overview", station: st });
const link = (st: string): Topic => ({ topic: "link", station: st });
const threads = (st: string): Topic => ({ topic: "threads", station: st });
const rows = (st: string): Topic => ({ topic: "chatRows", station: st });
const hostOf = (st: string): Topic => ({ topic: "host", station: st });
const prefs = (): Topic => ({ topic: "prefs" });
const sortedKeys = (topics: Topic[]) => topics.map(topicKey).sort();
const sorted = (topics: Topic[]) => [...topics].sort((a, b) => (topicKey(a) < topicKey(b) ? -1 : 1));
const sameTopics = (a: Topic[], b: Topic[], message?: string) => assert.deepEqual(sortedKeys(a), sortedKeys(b), message);

function stations(nowS: number): J {
  return {
    id: "ws",
    stations: [
      { id: "a", name: "alpha", last_seen: Math.trunc(nowS) - 10, version: "0.4.0" },
      { id: "b", name: "beta", last_seen: Math.trunc(nowS) - 1000, version: null },
      { id: "c", name: "gamma", last_seen: null, version: null },
    ],
  };
}
const oneStation = (): J => ({ id: "ws", stations: [{ id: "st", name: "studio", last_seen: null, version: null }] });
const session = (key: string): J => ({ key, connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null });
const member = (thread: number, key: string, connect: string): J => ({ thread, session: key, connect, joinedAt: 1 });
const fullSession = (key: string, patch: J = {}): J => ({
  key, connect: "c1", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
  profilePinned: false, model: null, effort: null, runtimeSessionId: null, workspace: "/w", running: false, createdAt: 1, lastActiveAt: 1, archivedAt: null,
  process: "cold", turns: 0, pending: 0, firstText: null, lastTurn: null, ...patch,
});
const turn = (id: string): J => ({ id, kind: "chat", outcome: null, declared: null, detail: null, startedAt: 1, endedAt: null });
const profile = (id: string, patch: J = {}): J => ({
  id, name: id, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null, models: [],
  env: [], usedBy: [], loginCommand: "", check: null, login: null, quota: null, ...patch,
});
const overviewOf = (connects: J[], profiles: J[]): J => ({
  viewer: { via: "local" }, connects, profiles, processes: [], counts: { sessions: 0, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [],
});
const hostInfo = (hostname: string): J => ({
  hostname, os: "macOS 26", arch: "arm64", cpus: 8, cpuModel: "M4", load: 0.2, uptimeSec: 100,
  memory: { totalBytes: 1024, usedBytes: 512, swapUsedBytes: null }, disk: { path: "/", totalBytes: 1024, freeBytes: 512 }, emberRssBytes: 10, checkedAt: 1,
});
const slackThread = (id: number): J => ({
  id, surface: "slack:T1", channel: "C1", channelName: "ops", threadTs: "1.0", title: null, createdBy: null, creator: null, createdAt: 1, sessions: [], last: 0,
  lastMessage: null, read: 0, unread: 0, people: [], firstText: null,
});
const connect = (id: string, name: string): J => ({
  id, name, team: null, enabled: true, kind: "slack", mode: "multi-session", requireMention: true, bind: { runtime: "claude", model: null, effort: null, profile: null },
  slack: { appToken: "", botToken: "" }, connection: { state: "no_tokens" }, createdBy: null, sessions: 0, session: null,
});
const thread = (id: number, keys: string[], at: number): J => ({
  id, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${id}.0`, title: null, createdAt: Math.trunc(at) - 10, creator: null,
  sessions: keys.map((k) => member(id, k, "ember")), last: id * 10,
  lastMessage: { seq: id * 10, thread: id, ts: `${id * 10}.0`, authorKind: "agent", author: keys[0] ?? "", authorName: null, text: "好的", attachments: [], quotes: [], declared: null, createdAt: Math.trunc(at), editedAt: null },
  read: 0, unread: 0, people: [], firstText: null,
});
function row(id: string, at: number): J {
  const th = /^[0-9]+$/.test(id) ? Number(id) : null;
  return { id, session: th !== null ? "s" : id, thread: th, title: `${id} 的标题`, agents: [session(id)], last: null, unread: false, mine: false, lastActiveAt: Math.trunc(at), connect: null, origin: null };
}
const said = (seq: number, kind: string, author: string, text: string, at: number): J => ({
  seq, thread: 7, ts: `9.${String(seq).padStart(6, "0")}`, authorKind: kind, author, authorName: null, text, attachments: [], quotes: [], declared: null, createdAt: Math.trunc(at), editedAt: null,
});
function deciding(id: string, th: number, seq: number, at: number, dismissed: boolean): J {
  const r = row(id, at);
  r.thread = th;
  r.session = id;
  const options = [{ label: "合", recommended: true }, { label: "先不改", detail: "留到下周" }];
  const message = { ...said(seq, "agent", id, `**${id}** 要合吗？\n细节`, at), options };
  r.decision = {
    seq, options, card: { type: "options", options, assignee: "me@x.com" }, message,
    before: [said(seq - 2, "person", "me@x.com", "改一下", at - 20), said(seq - 1, "agent", id, "好", at - 10)],
  };
  if (dismissed) r.decision.dismissed = true;
  return r;
}
const ids = (v: J): string[] => v.days.flatMap((d: J) => d.items.map((i: J) => i.id));

/// A value without what the clients show of it: what a view puts together, alone.
const SHOWN = new Set(["trouble", "settled", "archivable", "stateText", "face", "line", "available", "offered", "connection", "glyph", "note", "time", "statusText", "tone", "badgeText", "titleText", "agentText", "maker", "runtimeText", "processText", "efforts", "modeText", "modeShort", "runText", "presence", "checkText", "checkTone", "preview", "makers", "mark", "order", "left", "level", "refills", "shown", "processesText", "by", "waiting", "since", "originText", "summary", "modelsText"]);
function plain(v: J): J {
  if (Array.isArray(v)) return v.map(plain);
  if (v !== null && typeof v === "object") return Object.fromEntries(Object.entries(v).filter(([k, x]) => !SHOWN.has(k) && x !== null && x !== undefined).map(([k, x]) => [k, plain(x)]));
  return v;
}

test("canonical_and_legacy_station_notices_have_the_same_presentation", () => {
  const shown: J[] = [];
  for (const kind of ["ember", "stillfail"]) {
    const message: J = { authorKind: kind, author: kind, text: "notice" };
    shownMessage(message, [], null, [], [], [], undefined);
    assert.equal(message.system, true);
    assert.equal(message.mine, false);
    shown.push(message.by);
  }
  assert.deepEqual(shown[0], shown[1]);
});

test("another_chats_agent_goes_by_that_chats_name_without_the_header_line", () => {
  const agents = [{ session: { key: "k", agentText: "Opus", runtime: "claude" } }];
  for (const [text, title] of [
    ["来自 [发版 0.1.1780](https://x/o/w/s/a)：\n\n回归过了吗？", "发版 0.1.1780"],
    ["From <https://x/o/w/s/a|Release>:\n\n回归过了吗？", "Release"],
  ]) {
    const message: J = { authorKind: "agent", author: "far/a", text, agentIdentity: { model: "claude-opus-5-5" } };
    shownMessage(message, agents, null, [], [], [], undefined);
    assert.deepEqual([message.text, message.by.name, message.by.from], ["回归过了吗？", title, "https://x/o/w/s/a"]);
  }
  const own: J = { authorKind: "agent", author: "k", text: "来自 [a](https://x/o/w/s/a)：\n\nhi" };
  shownMessage(own, agents, null, [], [], [], undefined);
  assert.deepEqual([own.text, own.by.name], ["来自 [a](https://x/o/w/s/a)：\n\nhi", "Opus"]);
});

test("historical_messages_do_not_follow_the_current_model", () => {
  const message: J = { authorKind: "agent", author: "k", agentIdentity: { model: "gpt-6-sol", effort: "high" } };
  const agents = [{ session: { key: "k", agentText: "GPT-6 Astra", model: "gpt-6-astra", runtime: "claude", maker: { id: "openai", name: "OpenAI" } } }];
  shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, format.agentLabel("gpt-6-sol", "high"));
  assert.equal(message.by.runtime, "claude");
  delete message.agentIdentity;
  shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, "GPT-6 Astra");
  assert.equal(message.by.maker.id, "openai");
});

test("a_station_is_down_as_its_link_finds_it_or_as_it_was_last_until_then", () => {
  assert.ok(down({ state: "offline" }));
  assert.ok(!down({ state: "online" }));
  assert.ok(!down({ state: "reconnecting" }));
  assert.ok(!down({ state: "error" }));
  assert.ok(down({ state: "connecting", last: "offline" }));
  assert.ok(!down({ state: "connecting", last: "online" }));
  assert.ok(!down({ state: "connecting" }));
});

test("the_beta_switch_is_offered_to_an_account_in_the_beta_or_a_station_on_it", () => {
  const w = (channel: string | null) => ({ updates: [{ id: "claude" }, { id: "station", channel }] });
  assert.ok(!betaOffered(undefined, () => true));
  assert.ok(!betaOffered({}, () => true));
  assert.ok(!betaOffered(w(null), () => true));
  assert.ok(!betaOffered(w("stable"), () => false));
  assert.ok(betaOffered(w("stable"), () => true));
  assert.ok(betaOffered(w("beta"), () => false));
});

test("the_decisions_page_lists_those_waiting_for_the_viewer_set_aside_last", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "decisions", workspace: "ws" });
  await t.read(u, 1);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.read(u, 1);
  sameTopics(t.started(), [workspace(), prefs(), link("ws/st"), rows("ws/st"), overview("ws/st")]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const others = deciding("other", 11, 7, now - 12000, false);
  others.mine = true;
  others.decision.card.assignee = "other@x.com";
  const legacy = deciding("legacy", 12, 7, now - 14000, false);
  delete legacy.decision.card.assignee;
  t.set(rows("ws/st"), [deciding("k1", 7, 5, now - 1000, false), deciding("k2", 8, 3, now - 5000, false), deciding("k3", 9, 4, now - 9000, true), others, legacy, row("10", now)]);
  await t.read(u, 1);
  let v = u.value;
  const order = (x: J) => x.items.map((i: J) => i.session);
  assert.deepEqual(order(v), ["k2", "k1"]);
  assert.deepEqual([v.count, v.loading], [2, false]);
  const it = v.items[0];
  assert.deepEqual([it.station, it.stationName, it.thread, it.seq, it.title], ["ws/st", "studio", 8, 3, "k2 的标题"]);
  assert.equal(it.text, "奏 · k2 要合吗？");
  assert.deepEqual(it.options, [{ label: "先不改", detail: "留到下周" }, { label: "合", recommended: true }]);
  assert.equal(it.card.assigneeText, "需要你决策");
  assert.deepEqual(it.message.options, it.options);
  assert.deepEqual(it.message.decision, { resolved: false });
  assert.equal(it.message.by.agent, "k2");
  assert.deepEqual([it.before[0].mine, it.before.length], [true, 2]);
  t.set(prefs(), { decisionsDeferred: { [decisions.deferralKey("ws/st", 8, 3)]: 50 } });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(order(v), ["k1", "k2"]);
  assert.deepEqual([v.items[1].deferred, v.items[0].deferred], [true, undefined]);
});

test("the_decisions_page_has_the_starters_unassigned_cards_and_needs_without_one", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "decisions", workspace: "ws" });
  await t.read(u, 1);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.read(u, 1);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const me = { id: "me@x.com", name: "我", email: "me@x.com", via: "cloud" };
  const other = { id: "other@x.com", name: "小王", email: "other@x.com", via: "cloud" };
  const started = deciding("started", 7, 5, now - 9000, false);
  delete started.decision.card.assignee;
  started.creator = me;
  const theirs = structuredClone(started);
  Object.assign(theirs, { id: "theirs", session: "theirs", thread: 8, creator: other });
  const needs = row("needs", now - 5000);
  Object.assign(needs, { thread: 9, session: "needs", creator: me, need: { seq: 6, message: said(6, "agent", "needs", "要 Stripe 的测试 key", now - 5000), before: [] } });
  t.set(rows("ws/st"), [started, theirs, needs]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(v.items.map((i: J) => i.session), ["started", "needs"]);
  assert.equal(v.items[0].card.assigneeText, "需要你决策");
  const need = v.items[1];
  assert.deepEqual([need.seq, need.card, need.options], [6, { type: "text", assigneeText: "需要你决策" }, []]);
  assert.equal(need.text, "奏 · 要 Stripe 的测试 key");
});

test("the_decisions_page_says_what_was_answered_today_and_where_agents_are_at_work", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "decisions", workspace: "ws" });
  await t.read(u, 1);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.read(u, 1);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const options = [{ label: "先发测试版" }, { label: "不需要部署", action: "close" }];
  const done = row("7", now - 60_000);
  done.answered = [
    { seq: 3, text: "**0.1.1570** 先发测试版吗？\n细节", askedAt: now - 20 * 60_000, answeredAt: now - 10 * 60_000, card: { type: "options", options }, reply: "先发测试版", quoted: true },
    { seq: 5, text: "要部署吗？", askedAt: now - 4 * 60_000, answeredAt: now - 2 * 60_000, card: { type: "options", options }, closed: true },
    { seq: 1, text: "昨天的", askedAt: now - 30 * 3600_000, answeredAt: now - 26 * 3600_000, card: { type: "text" }, reply: "随便" },
  ];
  const busy = row("8", now - 1000);
  busy.mine = true;
  busy.agents[0].process = "running";
  busy.last = { text: "截三种首屏\n第二行" };
  const others = row("9", now - 500);
  others.agents[0].process = "running";
  t.set(rows("ws/st"), [done, busy, others]);
  await t.read(u, 1);
  const v = u.value;
  const answered = v.answered;
  // Today's only: as the viewer's clock has it (the host's offset here).
  const sameDay = (ms: number) => format.localDay(ms, t.host.utcOffsetMin(ms)) === format.localDay(now, t.host.utcOffsetMin(now));
  const expected = [
    ["选了「不需要部署」", now - 2 * 60_000],
    ["选了「先发测试版」", now - 10 * 60_000],
  ].filter(([, at]) => sameDay(at as number)).map(([a]) => a);
  assert.deepEqual(answered.map((a: J) => a.answer), expected);
  if (expected.length === 2) {
    assert.deepEqual([answered[1].text, answered[1].title, answered[1].seq], ["0.1.1570 先发测试版吗？", "7 的标题", 3]);
    assert.deepEqual(v.today, { count: 2, waited: "6 分钟", working: 1 });
  }
  assert.deepEqual([v.working[0].line, v.working.length], ["在做 · 截三种首屏", 1]);
});

test("a_rows_decision_is_its_line_and_mark_and_counts_for_the_workspace", async () => {
  const t = setup();
  const [chats, marks] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.subscribe(2, { topic: "workspaceMarks" });
  await t.readAll([[chats, 1], [marks, 2]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.readAll([[chats, 1], [marks, 2]]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const blocked = deciding("k1", 7, 5, now - 1000, false);
  blocked.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_decision", outcome: "completed", startedAt: 1, endedAt: 1 };
  blocked.mine = true;
  const others = deciding("other", 11, 7, now - 4000, false);
  others.decision.card.assignee = "other@x.com";
  t.set(rows("ws/st"), [blocked, deciding("k2", 8, 3, now - 2000, true), deciding("k3", 9, 4, now - 3000, false), others]);
  await t.readAll([[chats, 1], [marks, 2]]);
  const v = chats.value;
  const all = v.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  assert.deepEqual([of("k1").tone, of("k1").decision.text], ["wait", "奏 · k1 要合吗？"]);
  assert.deepEqual([of("k2").tone, of("k2").decision.dismissed, of("k2").decision.text], [undefined, true, undefined]);
  const m = marks.value;
  assert.equal(m.workspaces.ws.decisions, 2);
  assert.deepEqual([m.workspaces.ws.wait, m.workspaces.ws.alert, m.workspaces.ws.label], [2, 0, "2 个在等你"]);
});

function typing(id: string, th: number, seq: number, at: number): J {
  const r = row(id, at);
  r.thread = th;
  r.session = id;
  const card = { type: "text", placeholder: "sk_test_…", assignee: "me@x.com" };
  r.card = { seq, card, message: { ...said(seq, "agent", id, "Stripe 的测试 key 是多少？", at), card }, before: [] };
  return r;
}

test("a_text_card_is_on_the_page_and_its_row_whatever_its_agent_does", async () => {
  const t = setup();
  const [page, chats] = [ui(), ui()];
  t.subscribe(1, { topic: "decisions", workspace: "ws" });
  t.subscribe(2, { topic: "chats", scope: "ws" });
  await t.readAll([[page, 1], [chats, 2]]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.readAll([[page, 1], [chats, 2]]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const working = typing("k1", 7, 5, now - 1000);
  working.agents[0].process = "running";
  const needs = row("k2", now - 2000);
  needs.thread = 8;
  needs.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_help", need: "要 key", about: { thread: 8, seq: 9, ts: "9.000009" }, outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/st"), [working, needs]);
  await t.readAll([[page, 1], [chats, 2]]);
  let v = page.value;
  assert.equal(v.count, 1);
  const it = v.items[0];
  assert.deepEqual([it.card, it.options], [{ type: "text", placeholder: "sk_test_…", assignee: "me@x.com", assigneeText: "需要你决策" }, []]);
  assert.deepEqual([it.message.card, it.message.options, it.text], [it.card, undefined, "奏 · Stripe 的测试 key 是多少？"]);
  v = chats.value;
  const all = v.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  const k1 = of("k1");
  assert.deepEqual([k1.stateText, k1.stateAbout, k1.tone], ["奏 · Stripe 的测试 key 是多少？", 5, "wait"]);
  assert.deepEqual([k1.decision.card.type, k1.card], ["text", undefined]);
  const k2 = of("k2");
  assert.deepEqual([k2.stateText, k2.stateAbout, k2.tone], ["要你帮忙：要 key", 9, "wait"]);
});

test("what_is_worth_a_look_about_a_session_is_its_account_its_quota_running_out_and_the_disk_filling_up", () => {
  const ov = (check: string, week: number, free: number) => ({
    profiles: [{ id: "a", name: "A", check: { state: check, detail: "d" }, quota: { state: "ok", windows: [{ label: "5 小时", usedPercent: 10, resetsAt: 1 }, { label: "每周", usedPercent: week, resetsAt: 2 }] } }],
    disk: { freeBytes: free, totalBytes: 1000e9 },
  });
  const s = { profile: "a" };
  assert.deepEqual(attention(ov("ok", 50, 500e9), s, 0), []);
  assert.deepEqual(attention(ov("login", 92, 5e9), s, 0), [
    { kind: "account", text: "「A」要重新登录" },
    { kind: "quota", text: "每周剩余 8%", more: "马上刷新", quota: { left: 8, mark: "W", level: "red", until: 2 } },
    { kind: "disk", text: "磁盘剩 5 GB" },
  ]);
});

test("an_agent_can_be_moved_to_the_profiles_of_its_runtime", () => {
  const ov = {
    profiles: [
      { id: "a", name: "A", runtimes: ["claude", "codex"], models: ["m"] },
      { id: "b", name: "B", runtimes: ["codex"], models: ["m"], quota: { state: "ok", windows: [{ usedPercent: 100, resetsAt: 9000 }] } },
      { id: "c", name: "C", runtimes: ["claude"], models: ["m"] },
      { id: "d", name: "D", runtimes: ["codex"], models: ["other"] },
    ],
  };
  const s = { runtime: "codex", profile: "a", model: "m" };
  assert.deepEqual(runnableOn(ov, s, 0), [
    { id: "a", name: "A", current: true, spent: null, kind: null, runtime: null, quota: null, quotaLine: null, efforts: ["minimal", "low", "medium", "high", "xhigh"] },
    {
      id: "b", name: "B", current: false, spent: { until: 9000, text: "额度用完 · 1 分钟内恢复", back: "1 分钟内恢复" }, kind: null, runtime: null,
      quota: { state: "ok", windows: [{ usedPercent: 100, resetsAt: 9000 }] }, quotaLine: { text: "只剩 0%", level: "red" }, efforts: ["minimal", "low", "medium", "high", "xhigh"],
    },
  ]);
  assert.ok(choices(ov, s, 0).some((c: J) => c.model === "m" && c.accounts.codex.length === 2));
});

test("chats_puts_together_the_online_stations", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.read(u, 1);
  sameTopics(t.started(), [workspace(), prefs()]);
  assert.equal(u.value === undefined, true);
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string) => [rows(st), link(st), overview(st)];
  sameTopics(t.started(), [...each("ws/a"), ...each("ws/b"), ...each("ws/c")]);
  let v = u.value;
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  assert.equal(v.loading, true);
  assert.deepEqual(v.stations, [
    { station: "ws/a", id: "a", name: "alpha", state: "connecting" },
    { station: "ws/b", id: "b", name: "beta", state: "connecting" },
    { station: "ws/c", id: "c", name: "gamma", state: "connecting" },
  ]);
  assert.deepEqual(v.days, []);
  assert.deepEqual(v.note, { reading: true, text: "正在连接 3 台 station", failing: [], empty: false });
  assert.deepEqual([v.glyph.dim, v.glyph.online, v.glyph.summary], [3, 0, "3 台 station"]);
  t.set(link("ws/c"), { state: "offline" });
  const now = t.host.nowMs();
  const slack = row("s1", now - 2000);
  slack.connect = "c1";
  slack.origin = { teamName: "Acme", channel: "C1", channelName: "ops", threadTs: "1.0" };
  t.set(link("ws/a"), { state: "online" });
  t.set(rows("ws/a"), [row("1", now - 1000), slack]);
  t.set(link("ws/b"), { state: "online" });
  t.set(rows("ws/b"), [row("1", now - 1500)]);
  await t.read(u, 1);
  v = u.value;
  assert.equal(v.loading, false);
  assert.deepEqual([v.stations[0].state, v.stations[1].state], ["online", "online"]);
  let items = v.days[0].items;
  assert.deepEqual(ids(v), ["1", "1", "s1"]);
  assert.deepEqual([items[0].station, items[1].station, items[1].stationName], ["ws/a", "ws/b", "beta"]);
  const shown = { ...structuredClone(slack), station: "ws/a", stationName: "alpha", state: null, agents: [{ key: "s1", runtime: "claude", model: "opus", process: "cold", pending: 0 }] };
  assert.deepEqual(plain(items[2]), plain(shown));
  t.set(link("ws/b"), { state: "offline" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(ids(v), ["1", "1", "s1"]);
  assert.equal(v.stations[1].state, "offline");
  assert.equal(v.glyph.label, "3 台 station，1 台在线，2 台离线");
  assert.equal(v.note.reading, false);
  assert.deepEqual(v.trouble, { text: "2 台 station 异常", state: "offline", retry: false });
  items = v.days[0].items;
  assert.deepEqual([items[0].offline, items[1].offline], [undefined, "beta 离线"]);
  t.set(link("ws/b"), { state: "online" });
  await t.read(u, 1);
  assert.deepEqual(u.value.trouble, { text: "gamma 离线", state: "offline", retry: false });
  t.fail(rows("ws/a"), new CoreError("http_500", "坏了"));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.stations[0], { station: "ws/a", id: "a", name: "alpha", state: "error", message: "坏了" });
  assert.deepEqual(ids(v), ["1"]);
  t.set(rows("ws/a"), [row("1", now - 1000)]);
  t.set(link("ws/a"), { state: "reconnecting", message: "连接断开了" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([v.stations[0].state, v.stations[0].message], ["connecting", "连接断开了"]);
  assert.equal(ids(v).length, 2);
  assert.deepEqual(v.trouble, { text: "2 台 station 异常", state: "offline", retry: false });
  const reconnecting = (x: J) => x.days[0].items.map((i: J) => [i.station, i.reconnecting ?? null]);
  assert.ok(reconnecting(v).some(([s, r]: J) => s === "ws/a" && r === "正在重连 alpha…"), JSON.stringify(v));
  assert.ok(reconnecting(v).every(([s, r]: J) => s === "ws/a" || r === null));
  t.set(link("ws/a"), { state: "error", message: "没有权限" });
  await t.read(u, 1);
  assert.ok(reconnecting(u.value).some(([s, r]: J) => s === "ws/a" && r === "连不上 alpha，正在重试"));
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  assert.ok(reconnecting(u.value).every(([, r]: J) => r === null));
  t.fail(workspace(), new CoreError("not_found", "进不了这个工作区"));
  await t.read(u, 1);
  assert.equal(u.error.code, "not_found");
});

test("follows_the_workspaces_station_list", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  await t.read(u, 1);
  t.started();
  const withoutA = stations(t.nowS());
  withoutA.stations.splice(0, 1);
  t.set(workspace(), withoutA);
  await t.read(u, 1);
  assert.deepEqual(u.value.stations.map((s: J) => s.id), ["b", "c"]);
  assert.deepEqual(t.stopped(), []);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  sameTopics(t.stopped(), [rows("ws/a"), link("ws/a"), overview("ws/a")]);
});

test("groups_by_the_viewers_day_newest_first", async () => {
  const t = setup();
  t.host.setUtcOffsetMin(480);
  const now = t.host.nowMs();
  const offset = 480 * 60_000;
  const midnight = Math.floor((now + offset) / DAY_MS) * DAY_MS - offset;
  const today = midnight + (now - midnight) / 2;
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.set(rows("ws/st"), [row("1", midnight - 1000), row("2", midnight - 2 * DAY_MS - 1000), row("3", today), row("4", midnight - DAY_MS + 1000), row("a", midnight - 3 * DAY_MS - 1000)]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(
    v.days.map((d: J) => [d.daysAgo, d.items.map((i: J) => i.id)]),
    [[0, ["3"]], [1, ["1", "4"]], [3, ["2"]], [4, ["a"]]],
  );
  assert.equal(v.days[1].at, midnight - 1000);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  assert.deepEqual(v.stations, [{ station: "ws/st", id: "st", name: "studio", state: "online" }]);
});

test("dismissing_archive_reminders_restores_the_rows_color_and_order", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const done = row("done", now);
  done.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  const active = row("active", now - 1);
  for (const dismissed of [false, true]) {
    done.archiveReminderDismissed = dismissed;
    t.set(rows("ws/st"), [structuredClone(done), structuredClone(active)]);
    await t.read(u, 1);
    const v = u.value;
    assert.deepEqual(ids(v), dismissed ? ["done", "active"] : ["active", "done"]);
    const shown = v.days[0].items.find((r: J) => r.id === "done");
    assert.equal(shown.settled, dismissed ? undefined : true);
    assert.equal(shown.archivable, dismissed ? undefined : true);
    assert.equal(shown.stateText, "做完了");
  }
});

test("pinned_rows_go_above_the_days_the_latest_pinned_first", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const pinned = (id: string, at: number, p: J) => ({ ...row(id, at), pinned: p });
  t.set(rows("ws/st"), [pinned("1", now, null), pinned("2", now - 3 * DAY_MS, 5), pinned("3", now - 1000, 9), row("4", now - 2000)]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.days[0].label, v.days[0].daysAgo, v.days[0].pinned], ["已固定", -1, true]);
  assert.deepEqual(ids(v), ["3", "2", "1", "4"]);
  const flags = v.days.flatMap((d: J) => d.items.map((i: J) => ("pinned" in i ? i.pinned : "absent")));
  assert.deepEqual(flags, [true, true, false, "absent"]);
  assert.equal(v.days[1].pinned, undefined);
});

test("the_rows_are_led_by_the_agents_whatever_was_set", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.set(rows("ws/st"), []);
  await t.read(u, 1);
  assert.equal(u.value.leading, "agents");
  t.set(prefs(), { rowPicture: "people" });
  await t.read(u, 1);
  assert.equal(u.value.leading, "agents");
});

test("mine_keeps_the_rows_the_station_says_are_the_viewers", async () => {
  const t = setup();
  const [all, mine] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(all, 1);
  const now = t.host.nowMs();
  const w = (id: string, at: number, m: boolean) => ({ ...row(id, at), mine: m });
  t.set(rows("ws/a"), [w("1", now - 1, true), w("k", now - 2, false)]);
  t.set(rows("ws/b"), [w("1", now - 3, false), w("j", now - 4, true)]);
  await t.read(all, 1);
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  await t.read(mine, 2);
  assert.deepEqual(ids(all.value), ["1", "k", "1", "j"]);
  assert.deepEqual(ids(mine.value), ["1", "j"]);
  assert.equal(mine.value.days[0].items[1].station, "ws/b");
});

test("watching_keeps_the_rows_one_of_whose_agents_keeps_watch_marked_so", async () => {
  const t = setup();
  const [all, watching] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(all, 1);
  const now = t.host.nowMs();
  const ci = row("ci", now - 1);
  ci.agents[0].watch = { names: ["盯 CI"], since: Math.trunc(now) - 10, at: Math.trunc(now) - 5 };
  t.set(rows("ws/a"), [ci, row("plain", now - 2)]);
  await t.read(all, 1);
  t.subscribe(2, { topic: "chats", scope: "ws", watching: true });
  await t.read(watching, 2);
  assert.deepEqual(ids(all.value), ["ci", "plain"]);
  assert.equal(all.value.days[0].items[0].watch.text, "监控中：盯 CI");
  assert.equal(all.value.days[0].items[1].watch, undefined);
  assert.deepEqual(ids(watching.value), ["ci"]);
});

test("a_chats_unread_is_a_mark_and_its_title_comes_from_what_was_said", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  const named = { ...row("1", now - 1), title: "排查", unread: true, last: { seq: 7, authorKind: "agent", author: "a", authorName: null, text: "好的", createdAt: Math.trunc(now) - 1 } };
  const saidRow = { ...row("2", now - 2), title: "看看 这个" };
  t.set(rows("ws/st"), [named, saidRow]);
  await t.read(u, 1);
  const rowsOf = () => u.value.days[0].items.map((i: J) => [i.id, i.title, i.unread]);
  assert.deepEqual(rowsOf(), [["1", "排查", true], ["2", "看看 这个", false]]);
  t.data.putChat("ws/st", { ...named, unread: false });
  await t.read(u, 1);
  assert.equal(rowsOf()[0][2], false);
});

test("many_changes_are_one_computation_and_one_emission", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const [computed, messages] = [t.router.computed, u.messages];
  for (const st of ["ws/a", "ws/b"]) {
    t.set(link(st), { state: "online" });
    t.set(rows(st), [row("1", t.host.nowMs())]);
  }
  t.data.putChat("ws/a", { ...row("1", t.host.nowMs()), title: "改了" });
  await t.read(u, 1);
  assert.equal(t.router.computed, computed + 1);
  assert.equal(u.messages, messages + 1);
  assert.equal(u.value.days[0].items.length, 2);
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  assert.equal(t.router.computed, computed + 2);
  assert.equal(u.messages, messages + 1);
});

test("a_stopped_view_lets_its_topics_go", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string): Topic[] => [link(st), overview(st), hostOf(st), { topic: "net", station: st }];
  const watched = [workspace(), { topic: "workspaces" }, ...each("ws/a"), ...each("ws/b"), ...each("ws/c")];
  sameTopics(t.started(), watched);
  t.store.unsubscribe(1, 1);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  assert.deepEqual(t.stopped(), []);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  sameTopics(t.stopped(), watched);
  assert.deepEqual(t.store.liveTopics(), []);
});

test("stations_shows_each_station_with_its_models", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const quota = (windows: J[]) => ({ state: "ok", detail: null, checkedAt: 1, windows });
  const overviewA = overviewOf([], [
    profile("p1", { runtimes: ["codex"], models: ["o3", "gpt-5"], quota: quota([{ label: "5 小时", usedPercent: 40, resetsAt: 100 }, { label: "每周", usedPercent: 100, resetsAt: 5000 }]) }),
    profile("p2", { runtimes: ["claude"], models: [] }),
    profile("p3", { runtimes: ["claude"], models: ["sonnet"] }),
    profile("p4", { runtimes: ["claude"], models: ["opus", "sonnet"] }),
    profile("p5", { runtimes: ["claude", "codex"], models: ["deepseek-flash"] }),
    profile("p6", { runtimes: ["codex"], models: ["openai/gpt-5"], quota: quota([{ label: "每周", usedPercent: 100, resetsAt: 6000 }]) }),
  ]);
  t.set(overview("ws/a"), overviewA);
  t.set(hostOf("ws/a"), hostInfo("studio"));
  t.set(link("ws/a"), { state: "error", message: "没有权限" });
  t.set(link("ws/b"), { state: "offline" });
  await t.read(u, 1);
  const v = u.value;
  const seen = t.nowS();
  assert.ok(Math.abs(seen - v[0].lastSeen - 10) < 5);
  assert.equal(v[0].version, "0.4.0");
  assert.equal(v[0].online, true);
  assert.deepEqual(v[0].link, { state: "error", message: "没有权限" });
  // Reached, if refused: not coming back.
  assert.equal(v[0].reconnecting, false);
  assert.deepEqual(v[0].overview.profiles.map((p: J) => p.id), ["p1", "p2", "p3", "p4", "p5", "p6"]);
  assert.equal(v[0].host.hostname, "studio");
  assert.deepEqual(v[0].runtimes, [{ runtime: "claude", models: ["deepseek-flash", "opus", "sonnet"] }, { runtime: "codex", models: ["deepseek-flash", "gpt-5", "o3", "openai/gpt-5"] }]);
  const models = v[0].models.map((m: J) => ({ model: m.model, runtimes: m.runtimes, spent: m.spent?.until ?? null }));
  assert.deepEqual(models, [
    { model: "opus", runtimes: ["claude"], spent: null },
    { model: "sonnet", runtimes: ["claude"], spent: null },
    { model: "deepseek-flash", runtimes: ["claude", "codex"], spent: null },
    { model: "gpt-5", runtimes: ["codex"], spent: 5000 },
    { model: "o3", runtimes: ["codex"], spent: 5000 },
  ]);
  const gpt = v[0].models[3];
  assert.equal(gpt.family, "GPT");
  assert.deepEqual([gpt.maker.id, gpt.efforts.codex[0], gpt.accounts.codex[0].id], ["openai", "minimal", "p1"]);
  assert.ok(gpt.spent.text.startsWith("额度用完 · "));
  assert.deepEqual([gpt.name, gpt.ids], ["GPT-5", ["gpt-5", "openai/gpt-5"]]);
  assert.deepEqual(gpt.accounts.codex.map((a: J) => a.id), ["p1", "p6"]);
  assert.deepEqual(plain(v[1]), { station: "ws/b", id: "b", name: "beta", online: false, reconnecting: false, lastSeen: v[1].lastSeen, link: { state: "offline" }, runtimes: [], models: [], betaOffered: false });
  assert.ok(v[1].summary.startsWith("离线 · "));
  assert.equal(v[2].lastSeen, undefined);
});

test("the_beta_switch_follows_the_accounts_beta_at_once", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const o = overviewOf([], []);
  o.updates = [{ id: "station", name: "still.fail station", installed: true, version: "0.1.1", newer: false, updatable: true, state: "idle", channel: "stable" }];
  t.set(overview("ws/a"), o);
  await t.read(u, 1);
  assert.equal(u.value[0].betaOffered, false);
  t.beta.on = true;
  t.set({ topic: "workspaces" }, []);
  await t.read(u, 1);
  assert.equal(u.value[0].betaOffered, true);
});

test("connects_lists_every_online_stations_connects", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "connects", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string) => [link(st), overview(st), sessions(st), threads(st)];
  sameTopics(t.started(), [workspace(), ...each("ws/a"), ...each("ws/b"), ...each("ws/c")]);
  t.set(link("ws/c"), { state: "offline" });
  const me = { id: "Me@x.com", email: "Me@x.com" };
  assert.deepEqual(u.value as J, { me, items: [], loading: true });
  const c1 = { ...connect("c1", "one"), createdBy: { id: "me@x.com", name: "我" } };
  const c2 = connect("c2", "two");
  t.set(overview("ws/a"), overviewOf([c1, c2], []));
  t.fail(overview("ws/b"), new CoreError("offline", "连不上"));
  await t.read(u, 1);
  const v: J = u.value;
  assert.deepEqual(v.items.map((i: J) => [i.station, i.connect.id]), [["ws/a", "c1"], ["ws/a", "c2"]]);
  assert.deepEqual([v.loading, v.items[0].running, v.items[0].sessions.length], [false, 0, 0]);
  assert.equal(v.items[0].connect.createdBy.shown.display, "你");
  assert.equal(v.items[0].connect.statusText, "未连接 Slack");
  const mine = ui();
  t.subscribe(2, { topic: "connects", scope: "ws", mine: true });
  await t.read(mine, 2);
  assert.deepEqual(mine.value.items.map((i: J) => i.connect.id), ["c1"]);
});

test("times_in_words_go_out_fresh_each_minute", async () => {
  const t = setup();
  t.host.setUtcOffsetMin(480);
  t.store.setClock();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  await t.read(u, 1);
  const clock = (ms: number) => ms > 1000 && ms <= 61_000 && ms !== EVICT_AFTER_MS;
  const count = () => t.host.time.sleeps.filter(clock).length;
  const before = count();
  assert.ok(before >= 1, JSON.stringify(t.host.time.sleeps));
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  assert.equal(count(), before);
});

const sessionOf = (st: string, key: string): Topic => ({ topic: "session", station: st, key });
const pageOf = (st: string, id: number): Topic => ({ topic: "thread", station: st, thread: id });
const entry = (n: number, text: string): J => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "person", author: "a@x.com", authorName: null, text, at: n });
const page = (first: number, texts: string[], kept: J): J => ({ first, last: first + texts.length - 1, entries: texts.map((x, i) => entry(first + i, x)), thread: kept });
const chatTopic = (station: string, th: number): Topic => ({ topic: "chat", station, thread: th, session: null });
const agentPage = (station: string, key: string): Topic => ({ topic: "chat", station, thread: null, session: key });
const hasTopic = (list: Topic[], topic: Topic) => list.some((x) => topicKey(x) === topicKey(topic));

test("an_items_page_is_its_agents_and_becomes_its_chat", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  let v = u.value;
  assert.ok(v, "the agent alone");
  assert.deepEqual([v.thread ?? null, v.messages, v.title], [null, [], "修构建"]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: 7, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), pageOf("ws/a", 7)));
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), page(1, ["开始吧"], null));
  await t.read(u, 1);
  v = u.value;
  assert.equal(v.thread.id, 7);
  assert.equal(v.messages.length, 1);
});

test("a_card_answered_from_here_stays_answered_once_its_message_leaves_the_outbox", () => {
  const t = setup();
  const views = t.views;
  const id = views.outboxAdd("ws/st", 7, { text: "好" });
  assert.ok(views.local.answered("ws/st", 7, 4));
  views.outboxSent("ws/st", 7, id, 5);
  assert.equal(views.local.outboxGet("ws/st", 7, id), undefined);
  assert.ok(views.local.answered("ws/st", 7, 4));
  assert.ok(!views.local.answered("ws/st", 7, 6));
});

test("a_chat_renamed_or_pinned_here_shows_so_at_once_and_as_its_station_has_it_once_answered", async () => {
  const t = setup();
  const local = t.views.local;
  const list = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  t.set(rows("ws/st"), [row("7", now - 1000), row("8", now - 2000)]);
  await t.read(list, 1);
  const item = (id: string) => list.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === id);
  const renaming = local.changing("ws/st", 7, "s", { title: "新名字" }, null);
  const pinning = local.changing("ws/st", 8, "s", { pinned: now }, null);
  await t.read(list, 1);
  assert.equal(item("7").title, "新名字");
  assert.equal(item("8").pinned, true);
  local.changed(pinning, false, t.data.rowsRev("ws/st"));
  local.changed(renaming, true, t.data.rowsRev("ws/st"));
  await t.read(list, 1);
  assert.equal(item("7").title, "新名字");
  assert.notEqual(item("8").pinned, true);
  t.set(rows("ws/st"), [{ ...row("7", now - 1000), title: "站上的名字" }, row("8", now - 2000)]);
  await t.read(list, 1);
  assert.equal(item("7").title, "站上的名字");
});

test("an_agents_first_messages_show_at_once_and_go_on_into_its_chat_as_the_same_rows", async () => {
  const t = setup();
  const local = t.views.local;
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  const [first, ask] = local.firstQueue("ws/a", "k", { text: "修一下", attachments: [], quotes: [] });
  const [second, again] = local.firstQueue("ws/a", "k", { text: "还有", attachments: [], quotes: [] });
  assert.ok(ask && !again);
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox.map((m: J) => [m.id, m.state]), [[first, "sending"], [second, "sending"]]);
  local.firstFailed("ws/a", "k", "连不上");
  await t.read(u, 1);
  assert.equal(u.value.outbox[0].state, "failed");
  assert.ok(local.firstTry("ws/a", "k"));
  const sends = local.firstMade("ws/a", "k", 7);
  assert.deepEqual(sends.map(([id]) => id), [first, second]);
  assert.ok(!local.firstWaits("ws/a", "k"));
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: 7, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  t.set(threads("ws/a"), [thread(7, ["k"], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(1, ["开始吧"], null));
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.thread.id, 7);
  assert.deepEqual(v.outbox.map((m: J) => m.id), [first, second]);
});

test("an_old_notification_resolves_an_archived_chat_without_an_active_row", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), threads("ws/a")));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", archivedAt: 42 })]);
  t.set(rows("ws/a"), []);
  await t.read(u, 1);
  assert.equal(u.value === undefined, true, "must not show an empty agent while resolving the chat");
  const archived = { ...thread(7, ["k"], t.host.nowMs()), hiddenAt: 42 };
  t.set(threads("ws/a"), [archived]);
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), pageOf("ws/a", 7)));
  t.set(pageOf("ws/a", 7), page(1, ["原来的消息"], archived));
  await t.read(u, 1);
  const view = u.value;
  assert.equal(view.thread.id, 7);
  assert.equal(view.archived, true);
  assert.equal(view.messages.length, 1);
});

test("an_open_chat_tracks_archive_and_restore_without_losing_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const chat = thread(7, ["k"], t.host.nowMs());
  t.set(pageOf("ws/a", 7), page(1, ["kept message"], structuredClone(chat)));
  await t.read(u, 1);
  assert.equal(u.value.archived, false);
  for (const hidden of [42, null]) {
    chat.hiddenAt = hidden;
    t.set(threads("ws/a"), [structuredClone(chat)]);
    await t.read(u, 1);
    assert.equal(u.value.archived, hidden !== null);
    assert.equal(u.value.messages[0].text, "kept message");
  }
  chat.archivedAt = 42;
  t.set(threads("ws/a"), [chat]);
  await t.read(u, 1);
  assert.equal(u.value.archived, false);
});

test("a_chats_decisions_show_their_options_and_where_they_stand", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asked = { ...entry(2, "先 A 还是 B？"), authorKind: "agent", author: "k", declared: "block", ending: "need_decision", options: [{ label: "A", recommended: true }, { label: "B" }] };
  const picked = { ...entry(3, "B"), quotes: [{ author: "agent", text: "先 A 还是 B？", comment: "", ts: "2.0", role: "agent" }] };
  const again = { ...entry(4, "那 C 呢？"), authorKind: "agent", author: "k", options: [{ label: "C" }] };
  t.set(pageOf("ws/a", 7), { first: 1, last: 4, entries: [entry(1, "做吧"), asked, picked, again], thread: null });
  const chatRow = { ...row("k", now), thread: 7, decision: { seq: 4, options: [{ label: "C" }], message: { seq: 4, text: "那 C 呢？" }, before: [] } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  const m = v.messages;
  assert.deepEqual(m[1].options, [{ label: "B" }, { label: "A", recommended: true }]);
  assert.equal(m[1].ending, "need_decision");
  assert.deepEqual([m[1].decision.resolved, m[1].decision.chosen], [true, "B"]);
  assert.deepEqual(m[3].decision, { resolved: false });
  assert.deepEqual([m[1].card.type, m[3].card], ["options", { type: "options", options: [{ label: "C" }], assigneeText: "尚未指定决策人" }]);
  assert.equal(m[0].decision, undefined);
  assert.equal(v.decision.text, "奏 · 那 C 呢？");
  assert.equal(v.archivable, undefined);
});

test("chat_is_a_thread_its_messages_and_its_agents", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  sameTopics(t.started(), [threads("ws/a"), sessions("ws/a"), pageOf("ws/a", 7), rows("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs()]);
  assert.equal(u.value === undefined, true);
  const now = t.host.nowMs();
  const chat = { ...thread(7, ["k", "j"], now), title: "排查", people: [{ id: "local", name: "本机管理页", email: null, via: "local" }] };
  const kept = { ...structuredClone(chat), title: "排查（上次）" };
  t.set(pageOf("ws/a", 7), page(39, ["第 39 条", "第 40 条"], kept));
  await t.read(u, 1);
  let v = u.value;
  assert.deepEqual([v.title, v.messages.length, v.more], ["排查（上次）", 2, true]);
  sameTopics(t.started(), [sessionOf("ws/a", "k"), sessionOf("ws/a", "j")]);
  t.set(threads("ws/a"), [thread(3, ["x"], now), structuredClone(chat)]);
  await t.read(u, 1);
  assert.equal(u.value.title, "排查");
  const texts = Array.from({ length: 30 }, (_, i) => `第 ${i + 11} 条`);
  t.set(pageOf("ws/a", 7), page(11, texts, null));
  await t.read(u, 1);
  assert.deepEqual(u.value.agents, []);
  t.set(sessions("ws/a"), [fullSession("j", { connect: "ember" })]);
  await t.read(u, 1);
  let agents = u.value.agents;
  assert.deepEqual([agents.length, agents[0].session.key, agents[0].status], [1, "j", "idle"]);
  assert.ok(agents[0].connect === undefined && agents[0].profile === undefined);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { profile: "p2" }), threads: [structuredClone(chat)], turns: [turn("t1")] });
  t.fail(sessionOf("ws/a", "j"), new CoreError("http_404", "没有这个会话"));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  assert.equal(v.title, "排查");
  assert.deepEqual(plain(v.thread), plain(chat));
  assert.deepEqual(plain(v.people), plain(chat.people));
  assert.equal(v.people[0].shown.name, "本机管理页");
  assert.deepEqual(v.link, { state: "connecting" });
  assert.deepEqual([v.messages.length, v.more], [30, true]);
  assert.equal(v.agents.length, 1);
  assert.equal(v.agents[0].session.key, "k");
  assert.equal(v.agents[0].turns[0].id, "t1");
  assert.deepEqual(plain(v.agents[0].threads), plain([chat]));
  assert.deepEqual([v.agents[0].connect, v.agents[0].profile], [undefined, undefined]);
  t.set(overview("ws/a"), overviewOf([connect("c1", "Slack")], [profile("p1"), profile("p2", { name: "主力" })]));
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([v.agents[0].connect.id, v.agents[0].connect.name], ["c1", "Slack"]);
  assert.deepEqual([v.agents[0].profile.id, v.agents[0].profile.name], ["p2", "主力"]);
  assert.deepEqual(v.link, { state: "online" });
  // A new message goes out as an append.
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.push(entry(41, "新的"));
    (p as J).last = 41;
    return p;
  });
  await t.host.time.pass(100);
  const sent = t.host.takeEmitted();
  assert.equal(sent.length, 1);
  const delta = (sent[0][1] as J).delta;
  assert.ok(delta, JSON.stringify(sent[0]));
  const appended: J[] = merge([entry(41, "新的")]);
  appended[0].mine = false;
  appended[0].system = false;
  assert.deepEqual(plain(delta), plain([{ path: ["messages"], append: appended }]));
  u.value = applyOps(u.value, delta);
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.push({ n: 42, kind: "edit", target: 41, text: "新的（改）", attachments: [], quotes: [], at: 42 });
    (p as J).last = 42;
    return p;
  });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.messages.slice(-2).reverse().map((m: J) => [m.text, m.editedAt ?? null]), [["新的（改）", 42], ["第 40 条", null]]);
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.unshift(...Array.from({ length: 10 }, (_, i) => entry(i + 1, "旧的")));
    (p as J).first = 1;
    return p;
  });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([v.messages[0].seq, v.messages.length, v.more], [1, 41, false]);
  const seven = (t.data.thread("ws/a", 7) as J);
  t.data.putThread("ws/a", { ...seven, sessions: [...seven.sessions, member(7, "n", "ember")] });
  await t.read(u, 1);
  sameTopics(t.started(), [sessionOf("ws/a", "n")]);
  t.set(sessionOf("ws/a", "n"), { session: fullSession("n", { connect: "ember" }), threads: [], turns: [] });
  await t.read(u, 1);
  agents = u.value.agents;
  assert.deepEqual(agents.map((a: J) => a.session.key), ["k", "n"]);
  t.set(threads("ws/a"), [thread(3, ["k"], now)]);
  await t.read(u, 1);
  assert.equal(u.error.status, 404);
});

test("a_slack_chat_is_its_thread_like_any_other", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/st", 3));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const slack = { ...thread(3, ["k"], t.host.nowMs()), surface: "slack:T1", channel: "C1", channelName: "ops", firstText: "<@U0BOT> 部署挂了", sessions: [member(3, "k", "c1")] };
  t.set(threads("ws/st"), [slack]);
  t.set(pageOf("ws/st", 3), page(1, ["<@U0BOT> 部署挂了", "在看"], null));
  await t.read(u, 1);
  t.set(sessionOf("ws/st", "k"), { session: fullSession("k"), threads: [], turns: [] });
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.title, "部署挂了");
  assert.equal(v.thread.surface, "slack:T1");
  assert.equal(v.messages.length, 2);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
});

test("an_agent_without_a_chat_is_its_page_with_no_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  sameTopics(t.started(), [sessionOf("ws/a", "k"), rows("ws/a"), sessions("ws/a"), threads("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs()]);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k"), threads: [slackThread(3)], turns: [turn("t1")] });
  await t.read(u, 1);
  assert.equal(u.value === undefined, true, "its title is the station's: it waits for the items");
  const item = { ...row("k", t.host.nowMs()), title: "部署挂了" };
  t.set(rows("ws/a"), [row("7", t.host.nowMs()), item]);
  t.set(overview("ws/a"), overviewOf([connect("c1", "Slack")], []));
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.thread ?? null, v.title, v.messages, v.outbox, v.more], [null, "部署挂了", [], [], false]);
  const a = v.agents[0];
  assert.deepEqual([v.agents.length, a.session.key, a.connect.name, a.status], [1, "k", "Slack", "idle"]);
  assert.deepEqual([a.turns[0].id, a.threads[0].id], ["t1", 3]);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  for (const archived of [42, null]) {
    t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { archivedAt: archived }), threads: [], turns: [] });
    await t.read(u, 1);
    assert.equal(u.value.archived, archived !== null);
  }
  t.fail(sessionOf("ws/a", "k"), new CoreError("http_404", "这个会话已经删除了", 404));
  await t.read(u, 1);
  assert.equal(u.error.status, 404);
});

test("a_sent_message_shows_until_the_chat_has_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox, []);
  const views = t.views;
  const id = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  let out = u.value.outbox;
  assert.deepEqual([out[0].id, out[0].text, out[0].state], [id, "你好", "sending"]);
  views.local.outboxState("ws/a", 7, id, "连不上 station");
  await t.read(u, 1);
  out = u.value.outbox;
  assert.deepEqual([out[0].state, out[0].error], ["failed", "连不上 station"]);
  views.local.outboxState("ws/a", 7, id, null);
  views.outboxSent("ws/a", 7, id, 6);
  await t.read(u, 1);
  assert.equal(u.value.outbox[0].seq, 6);
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.push(entry(6, "你好"));
    (p as J).last = 6;
    return p;
  });
  await t.host.time.pass(100);
  const sent = t.host.takeEmitted();
  assert.equal(sent.length, 1);
  const ops = (sent[0][1] as J).delta as J[];
  assert.ok(ops, JSON.stringify(sent[0]));
  assert.ok(ops.some((op) => JSON.stringify(op.path) === '["messages"]'), JSON.stringify(ops));
  assert.ok(ops.some((op) => JSON.stringify(op.path) === '["outbox"]' && JSON.stringify(op.set) === "[]"), JSON.stringify(ops));
  const other = views.outboxAdd("ws/b", 1, { text: "x" });
  views.outboxSent("ws/b", 1, other, 1);
  assert.equal(views.local.outboxGet("ws/b", 1, other), undefined);
});

test("a_chat_asked_for_here_shows_at_once_and_becomes_its_stations_under_the_same_key", async () => {
  const t = setup();
  const local = t.views.local;
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  const [screen, list] = [ui(), ui()];
  t.subscribe(1, agentPage("ws/st", key));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  t.set(rows("ws/st"), [row("7", t.host.nowMs() - 1000)]);
  const both = () => t.readAll([[screen, 1], [list, 2]]);
  await both();
  let v = screen.value;
  assert.deepEqual([v.pending, v.key, v.outbox, v.title], [true, undefined, [], "新对话"]);
  assert.equal(list.value.days.length, 0);
  const first = local.pendingQueue(key, { text: "修一下登录\n细节…", attachments: [], quotes: [] })!;
  await both();
  v = screen.value;
  assert.deepEqual([v.title, v.outbox[0].id, v.outbox[0].state], ["修一下登录", first, "sending"]);
  let items = list.value.days[0].items;
  assert.deepEqual([items[0].id, items[0].pending, items[0].title], [key, true, "修一下登录"]);
  local.pendingFailed(key, "no claude profile configured");
  await both();
  const out = screen.value.outbox;
  assert.deepEqual([out[0].state, out[0].error], ["failed", "no claude profile configured"]);
  assert.equal(local.pendingTry(key)?.[0], "ws/st");
  await both();
  assert.equal(screen.value.outbox[0].state, "sending");
  const sends = local.pendingMade(key, "ember:c-1", 9);
  assert.deepEqual(sends.map(([id, m]) => [id, m.text]), [[first, "修一下登录\n细节…"]]);
  assert.equal(local.pendingThread("ws/st", key), 9);
  await both();
  v = screen.value;
  assert.deepEqual([v.pending, v.key, v.outbox[0].id], [false, "ember:c-1", first]);
  await both();
  assert.equal(list.value.days[0].items[0].id, "ember:c-1");
  t.set(threads("ws/st"), [thread(9, ["ember:c-1"], t.host.nowMs())]);
  t.set(pageOf("ws/st", 9), page(1, ["修一下登录\n细节…"], null));
  await both();
  v = screen.value;
  assert.deepEqual([v.key, v.thread.id, v.messages.length], ["ember:c-1", 9, 1]);
  const made = { ...row("ember:c-1", t.host.nowMs()), thread: 9, mine: true };
  t.set(rows("ws/st"), [made]);
  await both();
  items = list.value.days[0].items;
  assert.deepEqual([items.length, items[0].pending], [1, undefined]);
  t.set(rows("ws/st"), []);
  await both();
  assert.equal(list.value.days.length, 0);
});

test("the_stations_row_covers_a_chat_made_here_before_its_answer_comes", async () => {
  const t = setup();
  const local = t.views.local;
  const list = ui();
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const old = { ...row("ember:c-0", t.host.nowMs() - 5000), mine: true, thread: 3 };
  t.set(rows("ws/st"), [old]);
  await t.read(list, 2);
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  local.pendingQueue(key, { text: "修一下登录", attachments: [], quotes: [] });
  local.pendingTry(key);
  const idsOf = (): [string, string][] => list.value.days.flatMap((d: J) => d.items).map((i: J) => [i.id ?? "", i.title ?? ""]);
  await t.read(list, 2);
  assert.ok(idsOf().some(([i, ti]) => i === key && ti === "修一下登录"));
  const theirs = { ...row("ember:c-2", t.host.nowMs()), mine: true, thread: 8, title: "（还没有消息）" };
  t.set(rows("ws/st"), [old, theirs]);
  await t.read(list, 2);
  const cmp = (a: [string, string], b: [string, string]) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  assert.deepEqual(idsOf().sort(cmp), [["ember:c-0", "ember:c-0 的标题"], ["ember:c-2", "（还没有消息）"], [key, "修一下登录"]].sort(cmp as never));
  assert.equal(local.pendingTry(key)?.[1].clientKey, key);
  const made: J = { ...row("ember:c-1", t.host.nowMs()), mine: true, thread: 9, title: "（还没有消息）", clientKey: key };
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  const expected: [string, string][] = [["ember:c-0", "ember:c-0 的标题"], ["ember:c-1", "修一下登录"], ["ember:c-2", "（还没有消息）"]];
  assert.deepEqual(idsOf().sort(cmp), expected);
  local.pendingMade(key, "ember:c-1", 9);
  await t.read(list, 2);
  assert.deepEqual(idsOf().sort(cmp), expected);
  made.last = { seq: 1, text: "修一下登录", authorKind: "person", author: "Me@x.com", createdAt: Math.trunc(t.host.nowMs()) };
  made.title = "修一下登录（站上的）";
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  assert.ok(idsOf().some(([i, ti]) => i === "ember:c-1" && ti === "修一下登录（站上的）"));
});

test("a_chat_made_here_keeps_its_first_message_until_its_page_has_the_entry", async () => {
  const t = setup();
  const local = t.views.local;
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  const first = local.pendingQueue(key, { text: "修一下登录", attachments: [], quotes: [] })!;
  local.pendingMade(key, "ember:c-1", 9);
  t.views.outboxSent("ws/st", 9, first, 1);
  const screen = ui();
  t.subscribe(1, agentPage("ws/st", key));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  await t.read(screen, 1);
  let v = screen.value;
  assert.deepEqual([v.messages.length, v.outbox[0].id], [0, first]);
  t.set(threads("ws/st"), [thread(9, ["ember:c-1"], t.host.nowMs())]);
  t.set(pageOf("ws/st", 9), page(1, ["修一下登录"], null));
  await t.read(screen, 1);
  v = screen.value;
  assert.deepEqual([v.messages.length, v.outbox.length], [1, 0]);
});

test("outgoing_identity_survives_a_coalesced_acknowledgement", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const views = t.views;
  const id = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  views.outboxSent("ws/a", 7, id, 6);
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.push(entry(6, "你好"));
    (p as J).last = 6;
    return p;
  });
  await t.read(u, 1);
  const current = u.value;
  assert.deepEqual(current.outbox, []);
  assert.equal(current.messages.find((m: J) => m.seq === 6).outgoing, id);
  assert.equal(current.messages.find((m: J) => m.seq === 5).outgoing, undefined);
});

test("a_sent_message_that_arrives_before_its_seq_leaves_the_outbox_with_it", async () => {
  const t = setup();
  const u = ui();
  const topic = chatTopic("ws/a", 7);
  t.subscribe(1, topic);
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const views = t.views;
  const first = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  const second = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  assert.equal(u.value.outbox.length, 2);
  const mine = (n: number, text: string) => ({ ...entry(n, text), author: "Me@x.com" });
  t.store.update(pageOf("ws/a", 7), (p) => {
    (p as J).entries.push(entry(6, "你好"), mine(7, "你好"));
    (p as J).last = 7;
    return p;
  });
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox.map((m: J) => m.id), [second]);
  const messages = u.value.messages;
  assert.equal(messages.find((m: J) => m.seq === 7).outgoing, first);
  assert.equal(messages.find((m: J) => m.seq === 6).outgoing, undefined);
  assert.equal(views.local.outboxGet("ws/a", 7, first), undefined);
  const now = views.compute(topic) as J;
  assert.equal(now.ok.messages.find((m: J) => m.seq === 7).outgoing, first);
  views.outboxSent("ws/a", 7, first, 7);
  await t.read(u, 1);
  assert.equal(u.value.outbox.length, 1);
});

test("what_a_chats_agent_sent_to_slack_shows_after_the_message_it_followed_without_being_one_of_the_chats", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const said = (n: number, at: number, text: string) => ({ ...entry(n, text), at });
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [said(1, 1000, "发到 ops 说一声"), { ...said(2, 3000, "发了"), authorKind: "agent", author: "k" }], thread: null });
  const call = (tool: string, args: J, at: string, callId: string) => ({ at, kind: "tool_call", tool, text: JSON.stringify(args), callId });
  t.data.putItems("transcript", "ws/a", "k", [
    [0, call("mcp__stillfail__chat_post", { to: "C0OPS/1727.0001", text: "*部署* 好了 <https://x.y|看这里>" }, "1970-01-01T00:00:02Z", "c1")],
    [1, { at: "1970-01-01T00:00:02Z", kind: "tool_result", text: "posted", ok: true, callId: "c1" }],
    // Its own chat's words are its messages already; what goes to a still.fail chat is not Slack's.
    [2, call("mcp__stillfail__chat_post", { to: "EMBER/1.0", text: "这里" }, "1970-01-01T00:00:02.5Z", "c2")],
    [3, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", text: "新话题" } }, "1970-01-01T00:00:04Z", "c3")],
    // What someone said in Slack, given to it.
    [4, { at: "1970-01-01T00:00:05Z", kind: "user", text: '<message via="slack" thread="C0OPS/1727.0001" from="Mia (U9)" ts="2.5">*收到*，<@U9> 看一下</message>' }],
  ]);
  await t.read(u, 1);
  let v = u.value;
  assert.deepEqual(v.elsewhere.map((s: J) => [s.after, s.text, s.place.name, s.failed, s.received ?? false, s.by.name]), [
    [1, "**部署** 好了 [看这里](https://x.y)", "#C0OPS", false, false, v.elsewhere[0].by.name],
    [1, "**收到**，<@U9> 看一下", "#C0OPS", false, true, "Mia"],
    [2, "新话题", "#C0DEV", false, false, v.elsewhere[0].by.name],
  ]);
  assert.equal(v.messages.length, 2);
  // Slack's answer gives the new message its thread; one Slack refused failed.
  t.data.putItems("transcript", "ws/a", "k", [
    [5, { at: "1970-01-01T00:00:04Z", kind: "tool_result", text: JSON.stringify({ ok: true, ts: "1727.0002" }), callId: "c3" }],
    [6, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", thread_ts: "1727.0002", text: "补一句" } }, "1970-01-01T00:00:05Z", "c4")],
    [7, { at: "1970-01-01T00:00:05Z", kind: "tool_result", text: JSON.stringify({ ok: false, error: "not_in_channel" }), callId: "c4" }],
  ]);
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.elsewhere.map((s: J) => [s.after, s.text, s.failed]), [
    [1, "**部署** 好了 [看这里](https://x.y)", false],
    [1, "**收到**，<@U9> 看一下", false],
    [2, "新话题", false],
    [2, "补一句", true],
  ]);
});
