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
import { topicKey, type Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { EVICT_AFTER_MS, Store, type Source, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { attention, choices, runnableOn } from "../src/views/models.ts";
import { Views, betaOffered, blockedUnder, chatDerive, down, noticeOf, shownMessage } from "../src/views/views.ts";
import { installView, profile as presentProfile } from "../src/present.ts";
import { markdown } from "../src/markdown.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const DAY_MS = 86_400_000;

const VIEWS = new Set(["chats", "chatSearch", "stations", "stationNet", "connects", "chat", "history", "archive", "workspaceMarks", "chatJobs", "imageNear", "longJobs"]);

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
const SHOWN = new Set(["trouble", "settled", "archivable", "swipeArchive", "stateText", "stateLead", "stateRest", "face", "line", "available", "offered", "connection", "glyph", "note", "time", "statusText", "tone", "badgeText", "titleText", "agentText", "maker", "runtimeText", "processText", "efforts", "modeText", "modeShort", "runText", "presence", "checkText", "checkTone", "preview", "makers", "mark", "order", "left", "level", "refills", "shown", "processesText", "by", "waiting", "since", "originText", "originKind", "summary", "modelsText", "stateBusy", "problems", "changes", "modeWords", "modeLabel", "modeSentence", "placeText"]);
function plain(v: J): J {
  if (Array.isArray(v)) return v.map(plain);
  if (v !== null && typeof v === "object") return Object.fromEntries(Object.entries(v).filter(([k, x]) => !SHOWN.has(k) && x !== null && x !== undefined).map(([k, x]) => [k, plain(x)]));
  return v;
}

test("a notice that a runtime is not installed offers installing it as the station's updates have it", () => {
  const dsh = (over: J): J => ({ id: "dsh", name: "DeepSeek Harness", installed: false, updatable: true, state: "idle", ...over });
  // A manager can install it; a member is told who can; a station that cannot (no npm) says why.
  assert.deepEqual(installView("dsh", [dsh({})], true), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", action: "安装" });
  assert.deepEqual(installView("dsh", [dsh({})], false), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", note: "需由 workspace 的 owner 或管理员安装" });
  assert.deepEqual(installView("dsh", [dsh({ updatable: false, note: "未找到 npm" })], true), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", note: "未找到 npm" });
  // Installing, how far; failed, why, with trying again; then installed: each said in place of the notice's words.
  assert.deepEqual(installView("dsh", [dsh({ state: "updating", percent: 42 })], true), { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness", percent: 42 });
  assert.deepEqual(installView("dsh", [dsh({ state: "failed", message: "EACCES" })], true), { runtime: "dsh", state: "failed", title: "无法安装 DeepSeek Harness", detail: "EACCES", action: "重试" });
  assert.deepEqual(installView("dsh", [dsh({ installed: true, version: "0.2.0" })], true), { runtime: "dsh", state: "installed", title: "已安装 DeepSeek Harness" });
  // A station older than its updates: nothing offered.
  assert.equal(installView("dsh", [], true), null);
});

test("a notice that a runtime is not installed is said under the viewer's message that waits for it", () => {
  const install = { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", action: "安装" };
  const said = (over: J): J => ({ seq: 1, mine: false, waiting: false, ...over });
  // Folded into the last of the viewer's waiting before it (each notice of the runs that failed), gone from the chat.
  const folded = blockedUnder([said({ seq: 1, mine: true }), said({ seq: 2, mine: true, waiting: true }), said({ seq: 3, system: true, install }), said({ seq: 4, system: true, install })]);
  assert.deepEqual(folded.map((m) => [m.seq, m.blocked?.state ?? null]), [[1, null], [2, "missing"]]);
  // None of the viewer's waits (someone else's in Slack): it stays a notice; installed and nothing waits, it is gone.
  assert.deepEqual(blockedUnder([said({ seq: 1, waiting: true }), said({ seq: 2, system: true, install })]).map((m) => m.seq), [1, 2]);
  assert.deepEqual(blockedUnder([said({ seq: 1, mine: true }), said({ seq: 2, system: true, install: { ...install, state: "installed" } })]).map((m) => m.seq), [1]);
});

test("canonical_and_legacy_station_notices_have_the_same_presentation", () => {
  const shown: J[] = [];
  for (const kind of ["ember", "stillfail"]) {
    let message: J = { authorKind: kind, author: kind, text: "notice" };
    message = shownMessage(message, [], null, [], [], [], undefined);
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
    // The first message of a chat it opened (chat_create).
    ["由 [发版 0.1.1780](https://x/o/w/s/a) 开的 chat：\n\n回归过了吗？", "发版 0.1.1780"],
    ["Opened by [Release](https://x/o/w/s/a):\n\n回归过了吗？", "Release"],
  ]) {
    let message: J = { authorKind: "agent", author: "far/a", text, agentIdentity: { model: "claude-opus-5-5" } };
    message = shownMessage(message, agents, null, [], [], [], undefined);
    assert.deepEqual([message.text, message.by.name, message.by.from], ["回归过了吗？", title, "https://x/o/w/s/a"]);
  }
  let own: J = { authorKind: "agent", author: "k", text: "来自 [a](https://x/o/w/s/a)：\n\nhi" };
  own = shownMessage(own, agents, null, [], [], [], undefined);
  assert.deepEqual([own.text, own.by.name], ["来自 [a](https://x/o/w/s/a)：\n\nhi", "Opus"]);
});

test("a_slack_persons_message_shows_their_slack_picture_else_their_accounts", () => {
  const members = [{ email: "ada@x.com", name: "Ada", picture: "https://p/ada" }];
  const slack = shownMessage({ authorKind: "person", author: "U1", authorName: "Ada L", authorPicture: "https://avatars.slack-edge.com/ada_72.png", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(slack.by, { name: "Ada L", picture: "https://avatars.slack-edge.com/ada_72.png" });
  const page = shownMessage({ authorKind: "person", author: "ada@x.com", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(page.by, { name: "Ada", picture: "https://p/ada" });
  const unknown = shownMessage({ authorKind: "person", author: "U2", authorName: "Bo", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(unknown.by, { name: "Bo", picture: null });
});

test("historical_messages_do_not_follow_the_current_model", () => {
  let message: J = { authorKind: "agent", author: "k", agentIdentity: { model: "gpt-6-sol", effort: "high" } };
  const agents = [{ session: { key: "k", agentText: "GPT-6 Astra", model: "gpt-6-astra", runtime: "claude", maker: { id: "openai", name: "OpenAI" } } }];
  message = shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, format.agentLabel("gpt-6-sol", "high"));
  assert.equal(message.by.runtime, "claude");
  delete message.agentIdentity;
  message = shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, "GPT-6 Astra");
  assert.equal(message.by.maker.id, "openai");
});

test("an_agents_mark_is_drawn_from_what_its_message_says_before_its_session_is_read", () => {
  const message: J = { authorKind: "agent", author: "k", authorName: "Worker", authorModel: "gpt-5.5", authorRuntime: "codex", text: "hi" };
  const before = shownMessage(message, [], null, [], [], [], undefined);
  assert.deepEqual([before.by.name, before.by.maker?.id, before.by.runtime], ["Worker", "openai", "codex"]);
  // Once read, the session says.
  const agents = [{ session: { key: "k", agentText: "Opus", model: "claude-opus-5-5", runtime: "claude", maker: { id: "anthropic", name: "Anthropic" } } }];
  const after = shownMessage(message, agents, null, [], [], [], undefined);
  assert.deepEqual([after.by.maker.id, after.by.runtime], ["anthropic", "claude"]);
  // From a station that does not say: no mark yet.
  const old = shownMessage({ authorKind: "agent", author: "k", text: "hi" }, [], null, [], [], [], undefined);
  assert.deepEqual([old.by.maker, old.by.runtime], [null, null]);
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
  blocked.unread = true;
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
  assert.deepEqual([m.workspaces.ws.wait, m.workspaces.ws.alert, m.workspaces.ws.label], [2, 0, "2 个待你处理"]);
  // Of the lists the rail leads to: 我参与的 has the one of theirs waiting, 监控中 nothing.
  assert.deepEqual([m.workspaces.ws.tone, m.workspaces.ws.mineTone, m.workspaces.ws.watchingTone], ["wait", "wait", undefined]);
  // 待处理 and the badge are the same: the cards waiting for them not looked at since they came (k3 read: its row still
  // says it).
  assert.deepEqual([m.badge, m.workspaces.ws.badge], [1, 1]);
  assert.deepEqual(m.workspaces.ws.items.map((i: J) => [i.kind, i.session, i.seq, i.stationName]), [["wait", "k1", 5, "studio"]]);
  assert.equal(m.workspaces.ws.items[0].text, "奏 · k1 要合吗？", "its row's line");
  assert.equal(m.workspaces.ws.items[0].what, "k1 要合吗？", "the same without its lead");
});

test("待处理_is_what_went_wrong_till_let_go_or_waits_not_looked_at_since_of_what_the_badge_counts", async () => {
  const t = setup();
  const marks = ui();
  t.subscribe(1, { topic: "workspaceMarks" });
  await t.readAll([[marks, 1]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const failed = (id: string, at: number, unread: boolean): J => {
    const r = row(id, at);
    r.agents[0].lastTurn = { kind: "message", outcome: "failed", detail: "auth: 401", startedAt: 1, endedAt: 1 };
    r.mine = true;
    r.unread = unread;
    return r;
  };
  const waits = deciding("k1", 7, 5, now - 3000, false);
  waits.unread = true;
  t.set(rows("ws/st"), [failed("new", now - 1000, true), failed("old", now - 2000, false), waits]);
  await t.readAll([[marks, 1]]);
  const listed = () => marks.value.workspaces.ws.items.map((i: J) => [i.kind, i.session]);
  // gone wrong, read or not, till it runs again or is let go: as the workspace's mark says (pengxiao, 2026-10-28);
  // the badge only what was not read
  assert.deepEqual(listed(), [["alert", "new"], ["alert", "old"], ["wait", "k1"]]);
  assert.deepEqual([marks.value.workspaces.ws.alert, marks.value.workspaces.ws.label, marks.value.badge], [2, "2 个出错 · 1 个待你处理", 2]);
  const old = marks.value.workspaces.ws.items[1].failure;
  assert.equal(old, "ws/st/old@1", "a failure names its chat and when it ended");
  // let go (忽略): off 待处理 and the workspace's mark
  t.set(prefs(), { failsGone: { ws: [old] } });
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert, marks.value.workspaces.ws.label], [[["alert", "new"], ["wait", "k1"]], 1, "1 个出错 · 1 个待你处理"]);
  // the same chat failing again is another failure: back
  const again = failed("old", now - 500, false);
  again.agents[0].lastTurn = { ...again.agents[0].lastTurn, startedAt: 2, endedAt: 2 };
  t.set(rows("ws/st"), [failed("new", now - 1000, true), again, waits]);
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert], [[["alert", "old"], ["alert", "new"], ["wait", "k1"]], 2]);
  // run again (it ended well): no longer wrong
  const fine = row("old", now - 400);
  fine.mine = true;
  t.set(rows("ws/st"), [failed("new", now - 1000, true), fine, waits]);
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert], [[["alert", "new"], ["wait", "k1"]], 1]);
  // the badge counting only the cards: 待处理 has only them
  t.set(prefs(), { badgeKinds: { failed: false } });
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.badge], [[["wait", "k1"]], 1]);
});

// A message that did not go was said only in its chat, below what the agent last said: the list showed the agent's
// state (做完了) and no mark, so it went unseen there (2026-10-22).
test("a_chat_with_a_message_that_did_not_go_is_marked_on_its_row_until_it_goes", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const r = row("7", t.host.nowMs() - 1000);
  t.set(rows("ws/st"), [r]);
  await t.read(chats, 1);
  const of = () => chats.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === "7");
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined]);
  const id = t.views.outboxAdd("ws/st", 7, { text: "开始吧\n第二行", attachments: [], quotes: [] });
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined], "on its way, nothing to say");
  t.views.local.outboxState("ws/st", 7, id, "Office-VM-1 离线");
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText, of().unsent], ["alert", "未发送：开始吧 第二行", true]);
  t.views.local.outboxState("ws/st", 7, id, null);
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined], "sent again");
});

function typing(id: string, th: number, seq: number, at: number): J {
  const r = row(id, at);
  r.thread = th;
  r.session = id;
  const card = { type: "text", placeholder: "sk_test_…", assignee: "me@x.com" };
  r.card = { seq, card, message: { ...said(seq, "agent", id, "Stripe 的测试 key 是多少？", at), card }, before: [] };
  return r;
}

test("a_text_card_is_on_its_row_whatever_its_agent_does", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(2, { topic: "chats", scope: "ws" });
  await t.readAll([[chats, 2]]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.readAll([[chats, 2]]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const working = typing("k1", 7, 5, now - 1000);
  working.agents[0].process = "running";
  const needs = row("k2", now - 2000);
  needs.thread = 8;
  needs.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_help", need: "要 key", about: { thread: 8, seq: 9, ts: "9.000009" }, outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/st"), [working, needs]);
  await t.readAll([[chats, 2]]);
  const v = chats.value;
  const all = v.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  const k1 = of("k1");
  // A line that asks for a decision only says so: the chat leads to its post, not the row.
  assert.deepEqual([k1.stateText, k1.stateAbout, k1.tone], ["奏 · Stripe 的测试 key 是多少？", undefined, "wait"]);
  assert.deepEqual([k1.decision.card.type, k1.card], ["text", undefined]);
  const k2 = of("k2");
  assert.deepEqual([k2.stateText, k2.stateAbout, k2.tone], ["需要你处理：要 key", undefined, "wait"]);
});

test("what_is_worth_a_look_about_a_session_is_its_account_its_quota_running_out_and_the_disk_filling_up", () => {
  const ov = (check: string, week: number, free: number) => ({
    profiles: [{ id: "a", name: "A", check: { state: check, detail: "d" }, quota: { state: "ok", windows: [{ label: "5 小时", usedPercent: 10, resetsAt: 1 }, { label: "每周", usedPercent: week, resetsAt: 2 }] } }],
    disk: { freeBytes: free, totalBytes: 1000e9 },
  });
  const s = { profile: "a" };
  assert.deepEqual(attention(ov("ok", 50, 500e9), s, 0), []);
  assert.deepEqual(attention(ov("login", 92, 5e9), s, 0), [
    { kind: "account", text: "「A」需要重新登录" },
    { kind: "quota", text: "每周剩余 8%", more: "即将刷新", quota: { left: 8, mark: "W", level: "red", until: 2 } },
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
      id: "b", name: "B", current: false, spent: { until: 9000, text: "额度已用完 · 1 分钟内恢复", back: "1 分钟内恢复" }, kind: null, runtime: null,
      quota: { state: "ok", windows: [{ usedPercent: 100, resetsAt: 9000 }] }, quotaLine: { text: "剩余 0%", level: "red" }, efforts: ["minimal", "low", "medium", "high", "xhigh"],
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
    { station: "ws/a", id: "a", name: "alpha", state: "connecting", running: 0, doing: "正在连接" },
    { station: "ws/b", id: "b", name: "beta", state: "connecting", running: 0, doing: "正在连接" },
    { station: "ws/c", id: "c", name: "gamma", state: "connecting", running: 0, doing: "正在连接" },
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
  // A station given an emoji: its rows carry it (the rows made before are made again), and the stations list too.
  const withEmoji = stations(t.nowS());
  withEmoji.stations[1].emoji = "🍎";
  t.set(workspace(), withEmoji);
  await t.read(u, 1);
  assert.deepEqual(u.value.days[0].items.map((i: J) => i.stationEmoji ?? null), [null, "🍎", null]);
  // And an icon beside it: carried as it is (the clients draw it, or the emoji where they cannot).
  const withIcon = stations(t.nowS());
  withIcon.stations[1].emoji = "🍎";
  withIcon.stations[1].icon = "glyph:apple";
  t.set(workspace(), withIcon);
  await t.read(u, 1);
  assert.deepEqual(u.value.days[0].items.map((i: J) => i.stationIcon ?? null), [null, "glyph:apple", null]);
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
  assert.deepEqual(u.value.trouble, { text: "gamma 离线", state: "offline", retry: false, station: "ws/c" });
  t.fail(rows("ws/a"), new CoreError("http_500", "坏了"));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.stations[0], { station: "ws/a", id: "a", name: "alpha", state: "error", message: "坏了", running: 0, doing: "连不上" });
  assert.deepEqual(ids(v), ["1"]);
  t.set(rows("ws/a"), [row("1", now - 1000)]);
  t.set(link("ws/a"), { state: "reconnecting", message: "连接已断开" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([v.stations[0].state, v.stations[0].message], ["connecting", "连接已断开"]);
  assert.equal(ids(v).length, 2);
  assert.deepEqual(v.trouble, { text: "2 台 station 异常", state: "offline", retry: false });
  const reconnecting = (x: J) => x.days[0].items.map((i: J) => [i.station, i.reconnecting ?? null]);
  assert.ok(reconnecting(v).some(([s, r]: J) => s === "ws/a" && r === "正在重新连接 alpha"), JSON.stringify(v));
  assert.ok(reconnecting(v).every(([s, r]: J) => s === "ws/a" || r === null));
  t.set(link("ws/a"), { state: "error", message: "没有权限" });
  await t.read(u, 1);
  assert.ok(reconnecting(u.value).some(([s, r]: J) => s === "ws/a" && r === "无法连接 alpha，正在重试"));
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
  assert.deepEqual(v.stations, [{ station: "ws/st", id: "st", name: "studio", state: "online", running: 0, doing: "正在连接" }]);
});

test("a_chat_the_viewer_kept_out_of_the_archive_has_the_rows_color_and_order", async () => {
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
    // Kept by the viewer: the row says so (its menu lets it go).
    assert.equal(shown.kept, dismissed ? true : undefined);
    assert.equal(shown.stateText, "已完成");
  }
});

test("a_done_chat_is_offered_to_archive_as_the_archive_hint_says_and_archivable_whatever_it_says", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const done = row("done", now);
  done.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  const active = row("active", now - 1);
  t.set(rows("ws/st"), [done, active]);
  for (const [hint, offered] of [[undefined, true], ["off", false], ["reviewed", false], ["done", true]] as const) {
    t.set(prefs(), hint === undefined ? {} : { archiveHint: hint });
    await t.read(u, 1);
    const v = u.value;
    assert.deepEqual(ids(v), offered ? ["active", "done"] : ["done", "active"], String(hint));
    const shown = v.days[0].items.find((r: J) => r.id === "done");
    assert.equal(shown.settled, offered ? true : undefined, String(hint));
    assert.equal(shown.archivable, true, String(hint));
  }
});

test("an_ended_chat_is_swiped_away_unread_pinned_kept_or_not_recommended_alike_its_station_there", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  await t.host.time.pass(100);
  const done = (id: string, more: J): J => {
    const r = row(id, now);
    r.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
    return { ...r, ...more };
  };
  t.set(rows("ws/st"), [
    done("unread", { unread: true }),
    done("pinned", { pinned: 5 }),
    done("kept", { archiveReminderDismissed: true }),
    done("reviewed", { archiveReviewed: true, archiveRecommended: false }),
    row("active", now - 1),
  ]);
  await t.read(u, 1);
  const flags = (v: J): J => Object.fromEntries(v.days.flatMap((d: J) => d.items.map((i: J) => [i.id, [i.swipeArchive ?? false, i.archivable ?? false]])));
  // Each ended: swiped away, though none of them is offered to archive with one tap.
  assert.deepEqual(flags(u.value), {
    unread: [true, false], pinned: [true, false], kept: [true, false], reviewed: [true, false], active: [false, false],
  });
  // Its station offline: nothing there to take it.
  t.set(link("ws/st"), { state: "offline" });
  await t.read(u, 1);
  assert.equal(u.value.days.flatMap((d: J) => d.items).some((i: J) => i.swipeArchive === true), false);
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

test("a_chat_an_agent_opened_leads_back_to_its_opener_wherever_that_is_and_only_so", async () => {
  // Each chat stands on its own (its place, its archiving): the one opened only knows the way back to its opener, by
  // that one's title as its list has it, else as it was called; on its own station or another.
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("gone", now - 5000), title: "归档的发起者", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [
    { ...row("opener", now - 3000), title: "RPG 人物与剑术演示" },
    { ...row("here", now), opener: { session: "opener", title: "旧名字" } },
    { ...row("orphan", now - 1000), opener: { session: "gone", title: "当时的名字" } },
  ]);
  t.set(rows("ws/b"), [{ ...row("there", now - 2000), opener: { station: "a", session: "opener", title: "旧名字" } }]);
  await t.read(u, 1);
  const byId = new Map<string, J>(u.value.days.flatMap((d: J) => d.items).map((i: J) => [i.id, i]));
  assert.deepEqual(byId.get("here").opener, { station: "ws/a", session: "opener", title: "RPG 人物与剑术演示", text: "由「RPG 人物与剑术演示」创建" });
  assert.deepEqual(byId.get("there").opener, { station: "ws/a", session: "opener", title: "RPG 人物与剑术演示", text: "由「RPG 人物与剑术演示」创建" });
  assert.deepEqual(byId.get("orphan").opener, { station: "ws/a", session: "gone", title: "归档的发起者", text: "由「归档的发起者」创建", archived: true, note: "已归档" });
  assert.equal(byId.get("opener").opener, undefined);
  // Its own place in the list, newest first, whoever opened it.
  assert.deepEqual(ids(u.value), ["here", "orphan", "there", "opener"]);
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

test("a_station_refusing_for_a_security_mode_says_why_in_place_of_offline", async () => {
  // A station added to another workspace, taking none of its members yet, showed only 离线 there (2026-10-23).
  const t = setup();
  const list = ui();
  const chats = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.subscribe(2, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.readAll([[list, 1], [chats, 2]]);
  const why = "此 workspace 在此 station 加入后才开启安全模式，它不再接受此 workspace 的成员：请将它从此 workspace 移除后重新添加";
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/c"), { state: "online" });
  t.set(link("ws/b"), { state: "offline", cause: "lock", message: why });
  await t.readAll([[list, 1], [chats, 2]]);
  const b = (list.value as J[]).find((s) => s.station === "ws/b");
  assert.deepEqual([b.online, b.summary, b.line, b.blocked], [false, "安全模式未放行", "安全模式未放行", why]);
  const v = chats.value;
  assert.deepEqual(v.stations.find((s: J) => s.station === "ws/b"), { station: "ws/b", id: "b", name: "beta", state: "offline", message: why, cause: "lock", running: 0, doing: "安全模式未放行" });
  assert.deepEqual(v.trouble, { text: "安全模式未放行 beta", state: "offline", retry: false, station: "ws/b" });
  // Down for another reason: as before, nothing of a security mode.
  t.set(link("ws/b"), { state: "offline", cause: "unreached" });
  await t.readAll([[list, 1], [chats, 2]]);
  const again = (list.value as J[]).find((s) => s.station === "ws/b");
  assert.deepEqual([again.summary, again.blocked], ["连不上", undefined]);
  assert.equal(chats.value.trouble.text, "无法连接 beta");
});

test("a_stopped_view_lets_its_topics_go", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string): Topic[] => [link(st), overview(st), hostOf(st), { topic: "way", station: st }];
  const watched = [workspace(), { topic: "workspaces" }, ...each("ws/a"), ...each("ws/b"), ...each("ws/c")];
  sameTopics(t.started(), watched);
  t.store.unsubscribe(1, 1);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  assert.deepEqual(t.stopped(), []);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  sameTopics(t.stopped(), watched);
  assert.deepEqual(t.store.liveTopics(), []);
});

test("stations_say_how_each_is_reached_and_its_figures_are_a_view_of_their_own", async () => {
  // The list follows each station's way (seldom changing), not its readings: those are `stationNet`, for where they are
  // drawn.
  const t = setup();
  const u = ui();
  const card = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  t.set({ topic: "way", station: "ws/a" }, { path: "relay", relay: "relay.test" });
  await t.read(u, 1);
  const a = () => (u.value as J[]).find((s) => s.station === "ws/a");
  assert.deepEqual(a().way, { path: "中继 relay.test", via: "relay" });
  assert.equal("net" in a(), false);
  assert.equal(t.started().some((x) => x.topic === "net"), false);
  t.subscribe(2, { topic: "stationNet", station: "ws/a" });
  await t.read(card, 2);
  assert.equal(card.value, null);
  assert.deepEqual(t.started(), [{ topic: "net", station: "ws/a" }]);
  const computed = t.router.computed;
  const messages = u.messages;
  t.set({ topic: "net", station: "ws/a" }, { path: "relay", relay: "relay.test", rttMs: 286, rxBytes: 0, txBytes: 0, samples: [] });
  await t.readAll([[u, 1], [card, 2]]);
  const shown: J = card.value;
  assert.deepEqual([shown.path, shown.via, shown.rtt], ["中继 relay.test", "relay", { text: "286 ms", level: "ok" }]);
  assert.equal(t.router.computed, computed + 1, "the card's view alone");
  assert.equal(u.messages, messages);
});

test("a_held_topic_a_view_watches_goes_out_to_a_page_subscribing_later", async () => {
  // The station list watches the workspace; a station's page subscribing to the workspace itself then (its role, for
  // the ⋯ menu) has it at once, not when it next changes.
  const t = setup();
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), { ...oneStation(), role: "owner" });
  await t.read(list, 1);
  assert.equal(list.value.length, 1);
  const page = ui();
  t.subscribe(2, workspace());
  await t.read(page, 2);
  assert.equal(page.value?.role, "owner");
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
  assert.ok(gpt.spent.text.startsWith("额度已用完 · "));
  assert.deepEqual([gpt.name, gpt.ids], ["GPT-5", ["gpt-5", "openai/gpt-5"]]);
  assert.deepEqual(gpt.accounts.codex.map((a: J) => a.id), ["p1", "p6"]);
  assert.deepEqual(plain(v[1]), { station: "ws/b", id: "b", name: "beta", online: false, reconnecting: false, lastSeen: v[1].lastSeen, link: { state: "offline" }, runtimes: [], models: [], betaOffered: false, joined: false });
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
  assert.deepEqual(u.value as J, { me, items: [], wait: { reading: true, text: "正在从 3 台 station 读取", failing: [], empty: false } });
  const c1 = { ...connect("c1", "one"), createdBy: { id: "me@x.com", name: "我" } };
  const c2 = connect("c2", "two");
  t.set(overview("ws/a"), overviewOf([c1, c2], []));
  t.fail(overview("ws/b"), new CoreError("offline", "连不上"));
  await t.read(u, 1);
  const v: J = u.value;
  assert.deepEqual(v.items.map((i: J) => [i.station, i.connect.id]), [["ws/a", "c1"], ["ws/a", "c2"]]);
  assert.deepEqual([v.wait.reading, v.items[0].running, v.items[0].sessions.length], [false, 0, 0]);
  assert.deepEqual([v.wait.reading, v.wait.failing.map((f: J) => [f.station, f.message])], [false, [["ws/b", "连不上"]]]);
  assert.equal(v.items[0].connect.createdBy.shown.display, "你");
  assert.equal(v.items[0].connect.statusText, "未连接 Slack");
  // where it is reached and how it runs, in words; the ways it could be switched to, each with what that does
  assert.deepEqual([v.items[0].connect.placeText, v.items[0].connect.modeLabel], ["Slack", "每个 thread 一个会话"]);
  assert.deepEqual(v.items[0].changes.map((c: J) => [c.mode, c.requireMention, c.changed, c.effects.length]), [
    ["multi-session", true, false, 0],
    ["single-session", true, true, 2],
    ["single-session", false, true, 3],
  ]);
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

test("hidden_letters_keep_the_loaded_entry_cursors_advancing", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], t.host.nowMs())]);
  for (const last of [50, 100, 150]) {
    const entries = Array.from({ length: last }, (_, i) => ({
      ...entry(i + 1, "来自 [other](https://still.fail/o/ws/a/other)：\n\n更新"),
      authorKind: "agent", author: "other",
    }));
    t.set(pageOf("ws/a", 7), { first: 1, last, entries, end: false, thread: null });
    await t.read(u, 1);
    assert.equal(u.value.messages.length, 0, "letters do not add visible messages");
    assert.deepEqual([u.value.firstEntry, u.value.lastEntry], [1, last]);
  }
});

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

test("a_failure_notice_is_offered_to_report_where_the_station_takes_bug_reports", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const ember = (n: number, text: string): J => ({ ...entry(n, text), authorKind: "ember", author: "ember" });
  t.set(pageOf("ws/a", 7), { first: 1, last: 3, entries: [entry(1, "开始吧"), ember(2, "⚠️ 本轮出错：workspace routing discovery timed out"), ember(3, "已停止当前任务")], thread: null });
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const reportable = () => u.value.messages.map((m: J) => [m.seq, m.reportable ?? false]);
  // A station that takes none (another provider's, the beta channel, one from before): nothing offered.
  assert.deepEqual(reportable(), [[1, false], [2, false], [3, false]]);
  t.set(overview("ws/a"), { ...overviewOf([], []), feedback: true });
  await t.read(u, 1);
  assert.deepEqual(reportable(), [[1, false], [2, true], [3, false]]);
});

test("a_notice_comes_with_its_words_read_as_markdown_a_chat_it_opened_a_link_to_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  // (as the station says it opened one in a still.fail chat: sessions/opened.ts sayOpened)
  const link = "https://app.still.fail/o/ws/a/k2";
  const opened = `已创建对话：[共享调试：配对后连不上](${link})`;
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "开始吧"), { ...entry(2, opened), authorKind: "ember", author: "ember" }], thread: null });
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const notice = u.value.messages[1].notice;
  assert.equal(notice.words, opened);
  assert.deepEqual(notice.md, markdown(opened));
  assert.ok(JSON.stringify(notice.md).includes(`"href":"${link}"`));
  // (the words drawn are the notice's: the message's own not read besides)
  assert.equal(u.value.messages[1].md, undefined);
});

test("a_message_says_the_chats_it_links_to_their_titles_and_which_are_archived", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("c-old", now), title: "旧的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [row("c-live", now)]);
  const live = "https://app.still.fail/o/ws/a/c-live";
  const old = "https://app.still.fail/o/ws/a/c-old";
  // One linked bare, one archived in a reference, one no list has; a message with none says none.
  t.set(pageOf("ws/a", 7), page(1, [`看 ${live} 和 [那个](${old})，还有 https://app.still.fail/o/ws/a/c-none`, "没有链接"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  assert.deepEqual(u.value.messages.map((m: J) => m.chats), [[{ href: old, title: "旧的", archived: true, note: "已归档" }, { href: live, title: "c-live 的标题" }], undefined]);
});

test("a_chat_an_agent_opened_has_the_way_back_to_its_opener_over_its_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(rows("ws/a"), [{ ...row("k", now), thread: 7, opener: { session: "p", title: "当时的名字" } }, { ...row("p", now - 1000), title: "发起的对话" }]);
  t.set(pageOf("ws/a", 7), page(1, ["开始"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  assert.deepEqual(u.value.opener, { station: "ws/a", session: "p", title: "发起的对话", text: "由「发起的对话」创建" });
});

test("a_chat_whose_agent_opened_others_lists_them_each_where_it_stands", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("old", now), title: "归档的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [
    { ...row("k", now), thread: 7, opened: [{ session: "c-need", title: "当时的名字" }, { session: "old" }, { session: "gone", title: "没了的" }] },
    { ...row("c-need", now), title: "安卓构建", agents: [{ ...session("a1"), lastTurn: { kind: "message", declared: "block", ending: "need_help", need: "选一台测试机", outcome: "completed", startedAt: 1, endedAt: 2 } }] },
  ]);
  t.set(pageOf("ws/a", 7), page(1, ["开始"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.openedText, "创建了 3 个对话");
  assert.deepEqual(v.opened.map((o: J) => [o.session, o.title, o.stateLead ?? null, o.archived ?? false]), [
    ["c-need", "安卓构建", "need", false],
    ["old", "归档的", null, true],
    ["gone", "没了的", null, false],
  ]);
});

test("a_chat_that_links_others_reads_their_rows_alone_not_their_stations_lists", async () => {
  // A station's archive is thousands of rows: read whole to find a linked chat's title, it was most of what opening a
  // chat with a link in it took (0.65-0.83 s on a phone, 2026-10-31).
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("c-old", now), title: "旧的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [row("c-live", now)]);
  t.set(pageOf("ws/a", 7), page(1, ["看 https://app.still.fail/o/ws/a/c-live 和 https://app.still.fail/o/ws/a/c-old"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  // (as the app opens again: nothing of the lists read, the chat made anew)
  t.data.release({ topic: "archivedRows", station: "ws/a" });
  t.data.release(rows("ws/a"));
  t.store.invalidate(chatTopic("ws/a", 7));
  await t.read(u, 1);
  assert.deepEqual(u.value.messages[0].chats.map((c: J) => [c.title, c.archived ?? false]), [["c-live 的标题", false], ["旧的", true]]);
  assert.equal(t.data.loaded({ topic: "archivedRows", station: "ws/a" }), false, "the archive not read");
  assert.equal(t.store.inUse({ topic: "archivedRows", station: "ws/a" }), false, "nor shown: its station not asked for it whole");
  assert.equal(t.data.loaded(rows("ws/a")), false, "nor the list");
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
  // The card is in the chat: its line is not said at the end of the messages.
  assert.equal(v.stateText, undefined);
  // What waits undecided: the page leads to it, and its post says it can be let go there; no other post does.
  assert.deepEqual(v.asks, [{ seq: 4, card: true, mine: false, text: "那 C 呢？" }]);
  assert.deepEqual(m.map((x: J) => x.asked ?? false), [false, false, false, true]);
  // The last post, nothing after it: no room kept for the bell at the end.
  assert.equal(v.askClear, undefined);
});

test("an_agents_need_without_a_card_is_let_go_where_the_chats_end_says_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asks = { ...entry(2, "你在手机上试一下新的列表"), authorKind: "agent", author: "k", ending: "need_help" };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "做吧"), asks], thread: null });
  const agent = { ...session("k"), lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed", declared: "block", ending: "need_help", need: "在手机上试新列表" } };
  const chatRow = { ...row("k", now), thread: 7, agents: [agent], need: { seq: 2, message: { seq: 2, text: "你在手机上试一下新的列表" }, before: [] } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  // The reminder at the end of the messages says what it needs, and 忽略 goes with it, not under the post that asks.
  assert.deepEqual([v.stateLead, v.stateRest, v.stateAsk], ["need", "在手机上试新列表", 2]);
  assert.deepEqual(v.asks, [{ seq: 2, card: false, mine: false, text: "在手机上试新列表" }]);
  assert.deepEqual(v.messages.map((x: J) => x.asked ?? false), [false, false]);
  // It is the end itself, no bell over it there: the end keeps no room for one.
  assert.equal(v.askClear, undefined);
});

test("an_agents_need_let_go_stays_at_the_chats_end_said_as_let_go", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asks = { ...entry(2, "你在手机上试一下新的列表"), authorKind: "agent", author: "k", ending: "need_help" };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "做吧"), asks], thread: null });
  const agent = { ...session("k"), lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed", declared: "block", ending: "need_help", need: "在手机上试新列表" } };
  const chatRow = { ...row("k", now), thread: 7, agents: [agent], need: { seq: 2, message: { seq: 2, text: "你在手机上试一下新的列表" }, before: [], dismissed: true } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  // What it needed stays where the chat ends, said as let go; nothing more to let go, nothing asked.
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest, v.stateAsk], ["已忽略：在手机上试新列表", "dismissed", "在手机上试新列表", undefined]);
  assert.deepEqual(v.asks, []);
});

test("chat_is_a_thread_its_messages_and_its_agents", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  // The viewer's workspaces too: its sharing names the others (views/xshare.ts); its station's screens, its bar's way to them.
  sameTopics(t.started(), [threads("ws/a"), sessions("ws/a"), pageOf("ws/a", 7), rows("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs(), { topic: "workspaces" }, { topic: "screens", station: "ws/a" }]);
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
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(41, "新的")], last: 41 }));
  await t.host.time.pass(100);
  const sent = t.host.takeEmitted();
  assert.equal(sent.length, 1);
  const delta = (sent[0][1] as J).delta;
  assert.ok(delta, JSON.stringify(sent[0]));
  const appended: J[] = merge([entry(41, "新的")]);
  appended[0].mine = false;
  appended[0].system = false;
  assert.deepEqual(plain(delta), plain([{ path: ["lastEntry"], set: 41 }, { path: ["messages"], append: appended }]));
  u.value = applyOps(u.value, delta);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, { n: 42, kind: "edit", target: 41, text: "新的（改）", attachments: [], quotes: [], at: 42 }], last: 42 }));
  await t.read(u, 1);
  v = u.value;
  assert.equal(v.lastEntry, 42, "an edit advances the entry cursor without adding a message");
  assert.deepEqual(v.messages.slice(-2).reverse().map((m: J) => [m.text, m.editedAt ?? null]), [["新的（改）", 42], ["第 40 条", null]]);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...Array.from({ length: 10 }, (_, i) => entry(i + 1, "旧的")), ...(p as J).entries], first: 1 }));
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
  sameTopics(t.started(), [sessionOf("ws/a", "k"), rows("ws/a"), sessions("ws/a"), threads("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs(), { topic: "screens", station: "ws/a" }]);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k"), threads: [slackThread(3)], turns: [turn("t1")] });
  await t.read(u, 1);
  assert.equal(u.value === undefined, true, "its title is the station's: it waits for the items");
  const item = { ...row("k", t.host.nowMs()), title: "部署挂了", origin: { teamName: "AFK", channel: "C1", channelName: "ops", threadTs: "1.2" } };
  t.set(rows("ws/a"), [row("7", t.host.nowMs()), item]);
  t.set(overview("ws/a"), overviewOf([{ ...connect("c1", "Slack"), connection: { state: "connected", workspace: { team: "AFK", teamId: "T1", url: "https://afk.slack.com/", botUserId: "U0BOT", botName: "bot" } } }], []));
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.thread ?? null, v.title, v.messages, v.outbox, v.more], [null, "部署挂了", [], [], false]);
  const a = v.agents[0];
  assert.deepEqual([v.agents.length, a.session.key, a.connect.name, a.status], [1, "k", "Slack", "idle"]);
  assert.deepEqual([a.turns[0].id, a.threads[0].id], ["t1", 3]);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  // where its Slack thread is, and the way there, as a chat's info says them
  assert.deepEqual([v.place, v.slackUrl, v.feishuUrl], ["#ops", "https://afk.slack.com/archives/C1/p12", undefined]);
  assert.equal(v.slackApp, "slack://channel?team=T1&id=C1&message=1.2");
  assert.equal(v.noChat, undefined, "its Slack thread is its chat: the page does not open its history by itself");
  for (const archived of [42, null]) {
    t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { archivedAt: archived }), threads: [], turns: [] });
    await t.read(u, 1);
    assert.equal(u.value.archived, archived !== null);
    assert.equal(u.value.noChat, archived === null ? true : undefined);
  }
  t.fail(sessionOf("ws/a", "k"), new CoreError("http_404", "会话已删除", 404));
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
  views.local.outboxState("ws/a", 7, id, "无法连接 station");
  await t.read(u, 1);
  out = u.value.outbox;
  assert.deepEqual([out[0].state, out[0].error], ["failed", "无法连接 station"]);
  views.local.outboxState("ws/a", 7, id, null);
  views.outboxSent("ws/a", 7, id, 6);
  await t.read(u, 1);
  // The station took it: sent, kept until its entry comes.
  assert.deepEqual([u.value.outbox[0].seq, u.value.outbox[0].state], [6, "sent"]);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好")], last: 6 }));
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

// An image sent before it was up showed as a file card that turned into its picture once up (mbui, 2026-10-26): it is
// among the message's files from the first, in its shape, named by its upload; any other file going up stays a card.
test("an_image_sent_while_going_up_is_among_its_messages_files_at_once", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const up = { name: "a.txt", path: "/w/uploads/a.txt", size: 2 };
  const id = t.views.outboxAdd("ws/a", 7, { text: "看看", attachments: [up], quotes: [], uploads: [
    { id: "u1", name: "shot.PNG", size: 300, width: 1200, height: 800, sent: 100 },
    { id: "u2", name: "notes.pdf", size: 50, sent: 10 },
  ] });
  await t.read(u, 1);
  let [o] = u.value.outbox;
  assert.deepEqual(o.attachments, [up, { name: "shot.PNG", path: "upload:u1", size: 300, width: 1200, height: 800, upload: "u1" }]);
  assert.deepEqual(o.uploads.map((f: J) => [f.id, f.sent]), [["u2", 10]]);
  assert.deepEqual([o.waits, o.progress], ["正在上传 31%", 110 / 350]);
  // Up: the station's file in its place, still drawn from here (its upload); nothing left going up.
  t.views.local.outboxUploaded("ws/a", 7, id, [{ name: "shot.PNG", path: "/w/uploads/shot.png", size: 300, width: 1200, height: 800 }, { name: "notes.pdf", path: "/w/uploads/notes.pdf", size: 50 }]);
  await t.read(u, 1);
  [o] = u.value.outbox;
  assert.deepEqual(o.attachments.map((f: J) => [f.path, f.upload]), [["/w/uploads/a.txt", undefined], ["/w/uploads/shot.png", "u1"], ["/w/uploads/notes.pdf", "u2"]]);
  assert.deepEqual([o.uploads, o.waits], [undefined, undefined]);
  // Failed, it says so, not that it is going up.
  const failed = t.views.outboxAdd("ws/a", 7, { text: "再看", attachments: [], quotes: [], uploads: [{ id: "u3", name: "b.jpg", size: 9 }] });
  t.views.local.outboxState("ws/a", 7, failed, "连不上");
  await t.read(u, 1);
  const f = u.value.outbox.find((m: J) => m.id === failed);
  assert.deepEqual([f.attachments.map((a: J) => a.path), f.uploads, f.waits], [["upload:u3"], undefined, undefined]);
});

// A video sent with a new chat's first message showed as a file card (zuozijian, 2026-10-29): a new chat's files go up
// only as its message goes, so its video was still going up when its row came. Drawn as its message draws it once up:
// in its place and shape, its still the one picked here.
test("a_video_sent_while_going_up_is_among_its_messages_files_at_once", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  t.views.outboxAdd("ws/a", 7, { text: "", attachments: [], quotes: [], uploads: [{ id: "v1", name: "clip.MP4", size: 900, width: 1080, height: 1920, sent: 0 }] });
  await t.read(u, 1);
  const [o] = u.value.outbox;
  assert.deepEqual([o.attachments, o.uploads], [[{ name: "clip.MP4", path: "upload:v1", size: 900, width: 1080, height: 1920, upload: "v1" }], undefined]);
});

// A message going up said only 正在上传, however long it took (mbui, 2026-10-26): under it, how far all its files are
// together, as each says how much of it the station has; until every one has said (a station's file copied across says
// nothing until it is there), only that they go up.
test("a_message_going_up_says_how_far_its_files_are_together", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const id = t.views.outboxAdd("ws/a", 7, { text: "看看", attachments: [], quotes: [], uploads: [
    { id: "u1", name: "shot.png", size: 300, sent: 0 },
    { id: "u2", name: "notes.pdf", size: 100, sent: 50 },
  ] });
  await t.read(u, 1);
  const shown = () => { const o = u.value.outbox.find((m: J) => m.id === id); return [o.waits, o.progress]; };
  assert.deepEqual(shown(), ["正在上传 12%", 50 / 400]);
  t.views.local.uploadChanged("u1", { sent: 300 });
  await t.read(u, 1);
  assert.deepEqual(shown(), ["正在上传 87%", 350 / 400]);
  const copied = t.views.outboxAdd("ws/a", 7, { text: "再看", attachments: [], quotes: [], uploads: [
    { id: "u3", name: "a.png", size: 10, sent: 5 },
    { id: "u4", name: "b.zip", size: 10 },
  ] });
  await t.read(u, 1);
  const o = u.value.outbox.find((m: J) => m.id === copied);
  assert.deepEqual([o.waits, o.progress], ["正在上传", undefined]);
});

// The UIs keep an outgoing message's id past the core that gave it (a restarted core, the page still up): the Android
// chat's list crashed on two rows keyed o:out-1 when a new core counted from 1 again (2026-10).
test("a_message_sent_after_the_core_restarts_is_named_apart_from_one_sent_before", () => {
  const before = setup().views.outboxAdd("ws/a", 7, { text: "早" });
  const after = setup().views.outboxAdd("ws/a", 7, { text: "早" });
  assert.notEqual(before, after);
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
  // named by no one yet: a new chat, its page and its row, not the words sent (as its station calls it)
  assert.deepEqual([v.title, v.outbox[0].id, v.outbox[0].state], ["新对话", first, "sending"]);
  let items = list.value.days[0].items;
  assert.deepEqual([items[0].id, items[0].pending, items[0].title], [key, true, "新对话"]);
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
  assert.ok(idsOf().some(([i, ti]) => i === key && ti === "新对话"));
  const theirs = { ...row("ember:c-2", t.host.nowMs()), mine: true, thread: 8, title: "新对话" };
  t.set(rows("ws/st"), [old, theirs]);
  await t.read(list, 2);
  const cmp = (a: [string, string], b: [string, string]) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  assert.deepEqual(idsOf().sort(cmp), [["ember:c-0", "ember:c-0 的标题"], ["ember:c-2", "新对话"], [key, "新对话"]].sort(cmp as never));
  assert.equal(local.pendingTry(key)?.[1].clientKey, key);
  const made: J = { ...row("ember:c-1", t.host.nowMs()), mine: true, thread: 9, title: "新对话", clientKey: key };
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  const expected: [string, string][] = [["ember:c-0", "ember:c-0 的标题"], ["ember:c-1", "新对话"], ["ember:c-2", "新对话"]];
  assert.deepEqual(idsOf().sort(cmp), expected);
  local.pendingMade(key, "ember:c-1", 9);
  await t.read(list, 2);
  assert.deepEqual(idsOf().sort(cmp), expected);
  made.last = { seq: 1, text: "修一下登录", authorKind: "person", author: "Me@x.com", createdAt: Math.trunc(t.host.nowMs()) };
  made.title = "登录按钮";
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  assert.ok(idsOf().some(([i, ti]) => i === "ember:c-1" && ti === "登录按钮"));
  // its station no longer says the key (it keeps it only a while): the row still does, its page open by it
  const later: J = { ...made, title: "登录按钮 2" };
  delete later.clientKey;
  t.set(rows("ws/st"), [old, theirs, later]);
  await t.read(list, 2);
  const mine = list.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === "ember:c-1");
  assert.deepEqual([mine?.title, mine?.clientKey], ["登录按钮 2", key]);
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
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好")], last: 6 }));
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
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好"), mine(7, "你好")], last: 7 }));
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
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [said(1, 1000, "发到 ops 说一声"), { ...said(2, 3000, "<@U9> 发了"), authorKind: "agent", author: "k" }], thread: null });
  const call = (tool: string, args: J, at: string, callId: string) => ({ at, kind: "tool_call", tool, text: JSON.stringify(args), callId });
  t.data.putItems("transcript", "ws/a", "k", [
    [0, call("mcp__stillfail__chat_post", { to: "C0OPS/1727.0001", text: "*部署* 好了 <https://x.y|看这里>" }, "1970-01-01T00:00:02Z", "c1")],
    [1, { at: "1970-01-01T00:00:02Z", kind: "tool_result", text: "posted", ok: true, callId: "c1" }],
    // Its own chat's words are its messages already; what goes to a still.fail chat is not Slack's.
    [2, call("mcp__stillfail__chat_post", { to: "EMBER/1.0", text: "这里" }, "1970-01-01T00:00:02.5Z", "c2")],
    [3, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", text: "<@U9> 新话题" } }, "1970-01-01T00:00:04Z", "c3")],
    // What someone said in Slack, given to it.
    [4, { at: "1970-01-01T00:00:05Z", kind: "user", text: '<message via="slack" thread="C0OPS/1727.0001" from="Mia (U9)" ts="2.5">*收到*，<@U9> 看一下</message>' }],
  ]);
  await t.read(u, 1);
  let v = u.value;
  // Each under the message it followed (the chat's own `elsewhere`: what came before its first).
  const sent = (v: J): J[] => [...v.elsewhere, ...v.messages.flatMap((m: J) => m.elsewhere ?? [])];
  assert.deepEqual(v.elsewhere, []);
  assert.deepEqual(v.messages.map((m: J) => (m.elsewhere ?? []).length), [2, 1]);
  const agent = sent(v)[0].by.name;
  assert.deepEqual(sent(v).map((s: J) => [s.after, s.text, s.place.name, s.failed, s.received ?? false, s.by.name, s.by.here ?? false]), [
    [1, "**部署** 好了 [看这里](https://x.y)", "#C0OPS", false, false, agent, true],
    [1, "**收到**，@Mia 看一下", "#C0OPS", false, true, "Mia", false],
    [2, "@Mia 新话题", "#C0DEV", false, false, agent, true],
  ]);
  assert.equal(v.messages.length, 2);
  // Slack people the station's agents heard from are named in what agents say too.
  assert.equal(v.messages[1].text, "@Mia 发了");
  // The agent's own message: its name opens its history (one of the chat's).
  assert.equal(v.messages[1].by.here, true);
  // Slack's answer gives the new message its thread; one Slack refused failed.
  t.data.putItems("transcript", "ws/a", "k", [
    [5, { at: "1970-01-01T00:00:04Z", kind: "tool_result", text: JSON.stringify({ ok: true, ts: "1727.0002" }), callId: "c3" }],
    [6, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", thread_ts: "1727.0002", text: "<@U7> 补一句" } }, "1970-01-01T00:00:05Z", "c4")],
    [7, { at: "1970-01-01T00:00:05Z", kind: "tool_result", text: JSON.stringify({ ok: false, error: "not_in_channel" }), callId: "c4" }],
  ]);
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(sent(v).map((s: J) => [s.after, s.text, s.failed]), [
    [1, "**部署** 好了 [看这里](https://x.y)", false],
    [1, "**收到**，@Mia 看一下", false],
    [2, "@Mia 新话题", false],
    // Someone none of the station's agents heard from: by their Slack id.
    [2, "@U7 补一句", true],
  ]);
});

test("a_chats_page_is_told_by_each_message_whose_its_files_are_and_nothing_under_its_last_done_post", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const file = (path: string) => ({ name: path.split("/").pop(), path, size: 1 });
  const done = { ...entry(3, "好了"), authorKind: "agent", author: "k", declared: "final", ending: "all_done", attachments: [file("elsewhere/b.png")] };
  // Kept frozen, as the core keeps what it has read: what the page is told goes on copies (written on these, it threw
  // and took the core down).
  const frozen = <T,>(v: T): T => { if (v && typeof v === "object") { for (const x of Object.values(v)) frozen(x); Object.freeze(v); } return v; };
  t.set(pageOf("ws/a", 7), frozen({ first: 1, last: 3, entries: [{ ...entry(1, "看看"), attachments: [file("a.png")] }, { ...entry(2, "在看"), authorKind: "agent", author: "k" }, done], thread: null }));
  const settled = { ...row("k", now), thread: 7 };
  settled.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/a"), [settled]);
  await t.read(u, 1);
  const v = u.value;
  // Kept by the chat's agent: the only one, its workspace's or not.
  assert.deepEqual(v.messages.map((m: J) => m.attachments.map((a: J) => a.owner)), [["k"], [], ["k"]]);
  assert.equal(v.archivable, true);
  // Where it stands, as its row says it: at the end of its messages too.
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["已完成", "done", ""]);
  // Archived from its bar or the list: nothing offers it under its last all-done post, nor says what the check made of it.
  assert.equal(v.archiveOffered, undefined);
  assert.deepEqual(v.messages.map((m: J) => [m.archive, m.archiveCheck]), [[undefined, undefined], [undefined, undefined], [undefined, undefined]]);
});

test("a_chats_page_says_at_the_end_of_its_messages_what_its_agent_needs_as_its_row_does", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "部署一下"), { ...entry(2, "要 key"), authorKind: "agent", author: "k" }], thread: null });
  const blocked = { ...row("k", now), thread: 7 };
  blocked.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_help", need: "Stripe 的测试 key", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/a"), [blocked]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["需要你处理：Stripe 的测试 key", "need", "Stripe 的测试 key"]);
});

test("a_slack_threads_page_says_at_the_end_of_its_messages_where_it_stands_as_its_agents_row_does", async () => {
  // Its agent has no chat here: the list has it by its session alone (its row's thread null), the page by its thread.
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const done = { kind: "input", declared: "all_done", ending: "all_done", need: "问题已答完", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ds", lastTurn: done })]);
  t.set(threads("ws/a"), [{ ...slackThread(7), sessions: [member(7, "k", "ds")], last: 3 }]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 3, entries: [entry(1, "讲讲"), { ...entry(2, "讲完了"), authorKind: "agent", author: "k" }, entry(3, "我试试")], thread: null });
  const alone = row("k", now);
  alone.agents[0].lastTurn = done;
  t.set(rows("ws/a"), [alone]);
  await t.read(u, 1);
  const v = u.value;
  assert.equal(alone.thread, null);
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["已完成：问题已答完", "done", "问题已答完"]);
});

test("a_chats_page_says_what_its_agent_waits_on_once_in_its_activity_not_again_at_the_end", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const waits = { kind: "message", declared: "waiting", ending: "waiting", waitFor: "CI 跑完", waitSeconds: 600, outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", process: "warm", lastTurn: waits })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "合一下"), { ...entry(2, "等 CI"), authorKind: "agent", author: "k" }], thread: null });
  const waiting = { ...row("k", now), thread: 7 };
  waiting.agents[0].lastTurn = waits;
  waiting.agents[0].process = "warm";
  t.set(rows("ws/a"), [waiting]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(v.agents.map((a: J) => [a.status, a.wait?.text]), [["running", "等待：CI 跑完"]]);
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], [undefined, undefined, undefined]);
});

test("the_viewers_messages_sent_one_after_another_go_close_together_their_time_under_the_last", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, [], now)]);
  const minute = 60_000;
  const said = (n: number, at: number, author = "Me@x.com"): J => ({ ...entry(n, `第 ${n} 条`), author, at });
  // A minute apart, then four minutes on (within 5 of the last's time), then one 5 minutes later than the shown one
  // before it, someone else's, and two more of the viewer's.
  const at = [0, 1, 5, 11, 12, 13, 14].map((m) => now - 15 * minute + m * minute);
  t.set(pageOf("ws/a", 7), { first: 1, last: 7, entries: [said(1, at[0]), said(2, at[1]), said(3, at[2]), said(4, at[3]), said(5, at[4], "a@x.com"), said(6, at[5]), said(7, at[6])], thread: null });
  await t.read(u, 1);
  let v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.mine), [true, true, true, true, false, true, true]);
  // 1 and 2 are within 5 minutes of 3's time; 3 is 6 minutes before 4's, so it shows its own; 5 is someone else's.
  assert.deepEqual(v.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, false]);
  // Each close under the one before it that has its time under it.
  assert.deepEqual(v.messages.map((m: J) => m.joined ?? false), [false, true, true, false, false, false, true]);
  // One on its way follows the last one too; failed, it does not.
  const id = t.views.outboxAdd("ws/a", 7, { text: "还有", attachments: [], quotes: [] });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, true]);
  assert.deepEqual([v.outbox[0].joined, v.outbox[0].followed], [true, undefined]);
  t.views.local.outboxState("ws/a", 7, id, "无法连接 station");
  await t.read(u, 1);
  assert.deepEqual(u.value.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, false]);
  assert.equal(u.value.outbox[0].joined, undefined);
});

test("a_chats_page_is_told_which_files_its_agents_words_place_and_an_open_image_the_ones_beside_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const file = (name: string) => ({ name, path: `ws/k/${name}`, size: 1 });
  // The person's own words place nothing, even naming one; the agent's place theirs (not one named in code), in the
  // order named, ahead of the rest below them.
  const said = { ...entry(1, "![](a.png)"), attachments: [file("a.png"), file("notes.txt")] };
  const agent = { ...entry(2, "先看第二张 ![](c.png)，再看 [这张](ember-file://ws/k/b.png)\n\n`![](d.png)`"), authorKind: "agent", author: "k", attachments: [file("b.png"), file("c.png"), file("d.png"), file("e.mp4")] };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [said, agent], thread: null });
  t.set(rows("ws/a"), [{ ...row("k", now), thread: 7 }]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.placed ?? null), [null, ["c.png", "b.png"]]);
  // The page is not told every image; the one open in the preview, those beside it as the page shows them.
  assert.equal(v.images, undefined);
  const shown = async (name: string, id: number) => {
    const n = ui();
    t.subscribe(id, { topic: "imageNear", station: "ws/a", thread: 7, session: null, path: `ws/k/${name}` });
    await t.read(n, id);
    assert.equal(n.value.count, 4);
    return [n.value.before ? [n.value.before.name, n.value.before.owner] : null, n.value.after ? [n.value.after.name, n.value.after.owner] : null, n.value.index ?? null];
  };
  assert.deepEqual(await shown("a.png", 2), [null, ["c.png", "k"], 0]);
  assert.deepEqual(await shown("c.png", 3), [["a.png", "k"], ["b.png", "k"], 1]);
  assert.deepEqual(await shown("b.png", 4), [["c.png", "k"], ["d.png", "k"], 2]);
  assert.deepEqual(await shown("d.png", 5), [["b.png", "k"], null, 3]);
  // One not among them (gone meanwhile): none beside it.
  assert.deepEqual(await shown("x.png", 6), [null, null, null]);
});

test("an_agent_only_in_slack_shows_what_was_said_there_on_its_page", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  // Who wrote to it in Slack, with their Slack picture (the station's names book).
  const mia = { id: "slack:ember:U9", name: "Mia", email: null, via: "slack", picture: "https://avatars.slack-edge.com/mia_72.jpg" };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", participants: [mia] })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "看看项目", agents: [] }]);
  // Another agent's bot on the station, its picture as Slack shows it.
  const gpt = { ...connect("gpt", "GPT-Ember"), botImage: "https://avatars.slack-edge.com/gpt_72.jpg", connection: { state: "connected", botUserId: "UB2" } };
  t.set(overview("ws/a"), overviewOf([gpt], []));
  const call = (tool: string, args: J, at: string, callId: string) => ({ at, kind: "tool_call", tool, text: JSON.stringify(args), callId });
  t.data.putItems("transcript", "ws/a", "k", [
    [0, { at: "1970-01-01T00:00:01Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="Mia (U9)" ts="1.5">看看项目\n\nAttached files:\n- /ws/k/uploads/shot.png (shot.png, 13 bytes)</message>' }],
    [1, call("mcp__stillfail__chat_post", { to: "C0OPS/1.5", text: "*看了*" }, "1970-01-01T00:00:03Z", "c1")],
    [2, { at: "1970-01-01T00:00:03Z", kind: "tool_result", text: "posted", ok: true, callId: "c1" }],
    [3, { at: "1970-01-01T00:00:04Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="GPT-Ember (<@UB2>)" ts="4.0">也看了</message>' }],
    [4, { at: "1970-01-01T00:00:05Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="Mia (U9)" ts="5.0"><@UB2> 继续</message>' }],
  ]);
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.thread ?? null, null);
  assert.deepEqual(v.messages, []);
  assert.deepEqual(v.elsewhere.map((s: J) => [s.after, s.text, s.place.name, s.received ?? false, s.by.name]), [
    [0, "看看项目", "#C0OPS", true, "Mia"],
    [0, "**看了**", "#C0OPS", false, v.elsewhere[1].by.name],
    [0, "也看了", "#C0OPS", true, "GPT-Ember"],
    // Another agent's bot mentioned: by its name, as it was heard.
    [0, "@GPT-Ember 继续", "#C0OPS", true, "Mia"],
  ]);
  // The person's picture as their Slack shows it; the agent's mark, no picture; another agent's bot, its picture.
  assert.equal(v.elsewhere[0].by.picture, mia.picture);
  assert.equal(v.elsewhere[1].by.picture, undefined);
  assert.equal(v.elsewhere[2].by.picture, gpt.botImage);
  // The files the person sent with it are its files, kept by the session they were given to; not its words.
  assert.deepEqual(v.elsewhere.map((s: J) => s.attachments ?? []), [[{ name: "shot.png", path: "/ws/k/uploads/shot.png", size: 13, owner: "k" }], [], [], []]);
});

// ── What is shared is never written on (docs/core-ts.md「谁能改什么」) ──

/// mulberry32: the same draws for the same seed.
function draws(seed: number) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = a;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  const int = (n: number) => Math.floor(next() * n);
  return { int, chance: (p: number) => next() < p, pick: <T,>(list: T[]): T => list[int(list.length)] };
}

/// A chat and what is around it, of every kind there is, drawn from a seed: the views make their values from all of
/// it, kept frozen as the core keeps it (and every value the store keeps frozen too, in tests), so a write on any of
/// it anywhere throws, and the topic it is made for says so.
function drawnChat(seed: number, now: number) {
  const d = draws(seed);
  const keys = ["k", "j", "q"].slice(0, 1 + d.int(3));
  const file = (i: number) => ({ name: `f${i}.png`, path: d.chance(0.5) ? `/w/f${i}.png` : `elsewhere/f${i}.png`, size: i + 1 });
  const files = () => Array.from({ length: d.int(3) }, (_, i) => file(i));
  const quotes = () => (d.chance(0.3) ? [{ author: "agent", text: "那段", comment: d.chance(0.5) ? "嗯" : "", ts: "1.0", role: "agent" }] : []);
  const options = () => [{ label: "A", recommended: true }, { label: "B", detail: "再说" }];
  const entries: J[] = [];
  const n = 1 + d.int(12);
  for (let i = 1; i <= n; i++) {
    const kind = d.pick(["person", "agent", "agent", "stillfail", "edit"]);
    if (kind === "edit" && entries.length > 0) {
      entries.push({ thread: 7, n: i, kind: "edit", target: d.pick(entries).n, text: `改过的 ${i}`, attachments: files(), quotes: quotes(), at: i });
      continue;
    }
    const e: J = { ...entry(i, `第 ${i} 条 @Mia`), attachments: files(), quotes: quotes() };
    if (kind === "agent") {
      Object.assign(e, { authorKind: "agent", author: d.pick(keys), agentIdentity: d.chance(0.5) ? { model: "claude-opus-5-5", effort: "high" } : null });
      if (d.chance(0.3)) Object.assign(e, { declared: "final", ending: "all_done" });
      else if (d.chance(0.3)) Object.assign(e, { declared: "block", ending: "need_decision", options: options() });
      if (d.chance(0.2)) e.card = { type: d.pick(["options", "text"]), options: options(), assignee: d.pick(["me@x.com", "other@x.com"]) };
      if (d.chance(0.2)) e.text = "[来自 Slack](https://x.slack.com/a) 那边说的";
    } else if (kind === "stillfail") Object.assign(e, { authorKind: "stillfail", author: "stillfail" });
    else if (d.chance(0.5)) e.author = "me@x.com";
    entries.push(e);
  }
  const people = [{ id: "me@x.com", email: "me@x.com", name: "我", via: "web" }, { id: "local", name: "本机管理页", email: null, via: "local" }].slice(0, d.int(3));
  const th = { ...thread(7, keys, now), people, creator: d.chance(0.5) ? { id: "other@x.com", email: "other@x.com", name: "Other", via: "web" } : null };
  const turnOf = () => d.pick([null, { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1, need: "好了" }, { kind: "message", declared: "block", need: "选哪个", startedAt: 1, endedAt: null }]);
  const sessionsOf = keys.map((k) => fullSession(k, { connect: d.pick(["ember", "c1"]), profile: d.pick(["p1", "p2"]), model: d.pick([null, "claude-opus-5-5"]), process: d.pick(["cold", "running"]), lastTurn: turnOf(), lastActiveAt: now - d.int(100_000) }));
  const r: J = { ...row("k", now), thread: 7, title: "排查", agents: keys.map((k) => ({ ...session(k), lastTurn: turnOf(), process: d.pick(["cold", "running"]) })), unread: d.chance(0.5), mine: d.chance(0.5) };
  if (d.chance(0.5)) r.pinned = now - d.int(1000);
  if (d.chance(0.4)) r.decision = { seq: n, options: options(), message: { seq: n, text: "选哪个？", attachments: files() }, before: [], card: { type: "options", options: options() } };
  if (d.chance(0.4)) r.last = { seq: n, thread: 7, ts: `${n}.0`, authorKind: d.pick(["agent", "person"]), author: d.pick([...keys, "me@x.com"]), authorName: null, text: "最后一句", attachments: files(), quotes: [], declared: null, createdAt: now, editedAt: null };
  const quota = { state: "ok", windows: [{ label: "5h", usedPercent: d.int(100), resetsAt: now / 1000 + 3600 }, { label: "7d", usedPercent: d.int(100) }], credits: { hasCredits: d.chance(0.5), unlimited: false }, resetCount: d.int(3), checkedAt: 1 };
  const ov = {
    ...overviewOf([connect("c1", "Slack")], [profile("p1", { quota }), profile("p2", { name: "主力", access: { kind: "env", provider: "openrouter", key: "" }, check: { state: d.pick(["ok", "login", "failed"]), detail: "", models: ["claude-opus-5-5"], checkedAt: 1 } })]),
    footprint: d.chance(0.5) ? { bytes: d.int(1e9) } : {},
    machineLogins: [{ runtime: "claude", installed: true, loggedIn: true, plan: "max", email: "me@x.com", text: "me@x.com · max" }],
  };
  const outbox = Array.from({ length: d.int(3) }, (_, i) => ({ text: `还没发出的 ${i}`, attachments: files(), quotes: quotes() }));
  return { page: { first: 1, last: n, entries, thread: null }, thread: th, sessions: sessionsOf, row: r, overview: ov, outbox };
}

test("what_the_core_keeps_and_shares_is_never_written_on_whatever_a_chat_holds", async () => {
  const seeds = process.env.SIM_SEED ? [Number(process.env.SIM_SEED)] : Array.from({ length: 60 }, (_, i) => i + 1);
  for (const seed of seeds) {
    const t = setup();
    const now = t.host.nowMs();
    const drawn = drawnChat(seed, now);
    const topics: Topic[] = [
      chatTopic("ws/st", 7),
      { topic: "chats", scope: "ws" },
      { topic: "stations", scope: "ws" },
      { topic: "connects", scope: "ws" },
      overview("ws/st"),
      sessions("ws/st"),
      hostOf("ws/st"),
    ];
    const uis = topics.map((topic, i) => {
      t.subscribe(i + 1, topic);
      return [ui(), i + 1] as [Ui, number];
    });
    t.set(workspace(), oneStation());
    t.set(prefs(), {});
    t.set(link("ws/st"), { state: "online" });
    t.set(overview("ws/st"), drawn.overview);
    t.set(hostOf("ws/st"), hostInfo("studio"));
    t.set(sessions("ws/st"), drawn.sessions);
    t.set(threads("ws/st"), [drawn.thread]);
    t.set(rows("ws/st"), [drawn.row]);
    t.set(pageOf("ws/st", 7), drawn.page);
    for (const o of drawn.outbox) t.views.outboxAdd("ws/st", 7, o);
    await t.readAll(uis);
    const said = `seed ${seed} (SIM_SEED=${seed} runs it again)`;
    uis.forEach(([u], i) => {
      assert.equal(u.error, undefined, `${topicKey(topics[i])}: ${JSON.stringify(u.error)}; ${said}`);
      assert.notEqual(u.value, undefined, `${topicKey(topics[i])} has no value; ${said}`);
    });
    assert.equal(uis[0][0].value.messages.length, drawn.page.entries.filter((e: J) => e.kind === "message").length, said);
  }
});

test("a_station_says_how_it_is_and_what_is_wrong_with_it_in_the_cores_words", async () => {
  // StationCards.tsx's state() and problems() were the web's own (and its 15 s silence a timer of the page's): the
  // core's now, for the web's station page and the desktop app's alike.
  const t = setup();
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(list, 1);
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/b"), { state: "offline" });
  t.set(link("ws/c"), { state: "offline" });
  await t.read(list, 1);
  const of = (st: string) => (list.value as J[]).find((s) => s.station === st);
  // up, not read yet: connecting, nothing wrong yet
  assert.deepEqual([of("ws/a").stateText, of("ws/a").stateBusy, of("ws/a").problems], ["正在连接", false, []]);
  // away: when it was last online, red; never online, amber
  assert.ok(of("ws/b").stateText.endsWith("在线"), of("ws/b").stateText);
  assert.deepEqual(of("ws/b").problems.map((p: J) => [p.key, p.level]), [["away", "red"]]);
  assert.deepEqual([of("ws/c").stateText, of("ws/c").problems.map((p: J) => [p.key, p.level])], ["尚未上线", [["away", "amber"]]]);
  // up and no host reading for 15 s: silent
  await t.host.time.pass(15_000);
  await t.read(list, 1);
  assert.deepEqual(of("ws/a").problems.map((p: J) => [p.key, p.level]), [["silent", "amber"]]);
  // its host read and its agents at work: busy, nothing wrong
  t.set(hostOf("ws/a"), hostInfo("studio"));
  t.set(overview("ws/a"), { ...overviewOf([], []), counts: { sessions: 2, running: 2, warm: 0 } });
  await t.read(list, 1);
  assert.deepEqual([of("ws/a").stateText, of("ws/a").stateBusy, of("ws/a").problems], ["2 个 agent 正在运行", true, []]);
});

test("a_profile_says_what_it_is_who_signs_it_in_and_its_last_check_in_the_cores_words", () => {
  // Accounts.tsx worked these out itself (ACCESS labels, signInProvider, the check's detail without 可用): the core's
  // now, for the web's page and the desktop app's.
  const sub = presentProfile(profile("p1", { check: { state: "ok", detail: "可用，Claude Max", models: [] } }));
  assert.deepEqual([sub.kindText, sub.signInProvider, sub.checkLine], ["订阅账号", "Claude", "Claude Max"]);
  const codex = presentProfile(profile("p2", { runtime: "codex", runtimes: ["codex"] }));
  assert.deepEqual([codex.signInProvider, codex.checkLine], ["ChatGPT", "尚未检查"]);
  const machine = presentProfile(profile("p3", { machine: true }));
  assert.equal(machine.kindText, "终端里的登录");
  const go = presentProfile(profile("p4", { access: { kind: "opencode-go", key: "" } }));
  assert.deepEqual([go.kindText, go.signInProvider], ["OpenCode Go", "OpenCode"]);
  // the station's detail in English starts with its Works, as the Chinese with 可用
  const en = presentProfile(profile("p5", { check: { state: "ok", detail: "Works, 3 models", models: [] } }));
  assert.equal(en.checkLine, "3 models");
});

test("still.fail's notice is shown as a line: a failure's mark taken off, no closing 。, a profile's link after its ：", () => {
  assert.deepEqual(noticeOf("⚠️ 运行失败：额度用完了。", false), { failed: true, words: "运行失败：额度用完了" });
  assert.deepEqual(noticeOf("已切换模型", false), { failed: false, words: "已切换模型" });
  assert.deepEqual(noticeOf("⚠️ 登录 Work 失败：令牌过期。 ", true), { failed: true, words: "登录 Work 失败：令牌过期", linkAt: 11 });
  assert.deepEqual(noticeOf("登录失败", true), { failed: false, words: "登录失败" });
  const m = shownMessage({ authorKind: "stillfail", author: "stillfail", text: "⚠️ 出错了。", seq: 3 }, [], {}, [], [], [], null);
  assert.deepEqual(m.notice, { failed: true, words: "出错了" });
});
