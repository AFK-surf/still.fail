// An ask open for the viewer, one rule for the chat, the 奏 page and the marks (Views.openAsk): a card or the need an
// agent ended need_help with, not dismissed, theirs to decide, not answered from here. "计数看着还是不对：需要 decision 的，
// 新发了消息 decision 就不见了，但还留在 decision 过滤里" (desktop 0.1.2224). Shapes follow test/views.test.ts and the
// user's real rows (threads 19 / 24 of their station).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Data, holds } from "../src/data.ts";
import { apply as applyOps, type Op } from "../src/delta.ts";
import { holdLanguage } from "../src/i18n.ts";
import { type Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { Store, type Source, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Views, chatDerive } from "../src/views/views.ts";
import * as decisions from "../src/decisions.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const VIEWS = new Set(["chats", "chat", "workspaceMarks", "decisions"]);

function setup() {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  store.setShaped();
  const data = new Data(host, runner, { owner: () => "s1", derive: chatDerive });
  Effect.runSync(data.open(["s1"]));
  store.setHeld((topic) => data.shared(topic), (topic) => data.release(topic));
  data.onChange((topic) => store.changed(topic));
  const views = new Views({ host, runner, store, data, emailOf: (ws) => (ws === "ws" ? "me@x.com" : null), betaOf: () => false, relayName: () => null });
  const source: Source = {
    start: (topic: Topic) => (VIEWS.has(topic.topic) ? views.start(topic) : undefined),
    stop: (topic: Topic) => (VIEWS.has(topic.topic) ? views.stop(topic) : undefined),
    compute: (topic: Topic): Value | undefined => (VIEWS.has(topic.topic) ? views.compute(topic) : undefined),
  };
  store.setSource(source);
  const values = new Map<number, J>();
  const t = {
    host, data, views,
    subscribe: (id: number, topic: Topic) => store.subscribe(1, id, topic),
    set: (topic: Topic, value: unknown) => (holds(topic) ? data.set(topic, value) : store.set(topic, { ok: value })),
    async read(): Promise<void> {
      await host.time.pass(100);
      for (const [, message] of host.takeEmitted()) {
        const m = message as J;
        if (m.error?.code === "shape") throw new Error(m.error.message);
        if ("value" in m) values.set(m.id, m.value);
        else if ("delta" in m) values.set(m.id, applyOps(values.get(m.id), m.delta as Op[]));
      }
    },
    value: (id: number) => values.get(id),
  };
  return t;
}

const ST = "ws/st";
const TH = 19;
const me = { id: "me@x.com", name: "我", email: "me@x.com", via: "cloud" };
const entry = (n: number, kind: string, text: string, extra: J = {}): J => ({
  thread: TH, n, kind: "message", ts: `${n}.0`, authorKind: kind, author: kind === "agent" ? "k" : "me@x.com", authorName: null, text, at: n, ...extra,
});
const said = (seq: number, kind: string, text: string): J => ({
  seq, thread: TH, ts: `${seq}.0`, authorKind: kind, author: kind === "agent" ? "k" : "me@x.com", authorName: null, text, attachments: [], quotes: [], declared: null, createdAt: seq, editedAt: null,
});
const agent = (patch: J = {}): J => ({ key: "k", connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null, ...patch });
const needHelp = (need: string, about: J = undefined): J => ({ kind: "input", outcome: "completed", declared: "block", ending: "need_help", need, ...(about ? { about } : {}), startedAt: 1, endedAt: 2 });
const baseRow = (patch: J): J => ({ id: "k", session: "k", thread: TH, title: "桌面版右键菜单", agents: [agent()], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null, creator: me, people: [me], ...patch });
const threadOf = (last: number): J => ({
  id: TH, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${TH}.0`, title: null, createdAt: 1, creator: me,
  sessions: [{ thread: TH, session: "k", connect: "ember", joinedAt: 1 }], last, lastMessage: null, read: 0, unread: 0, people: [me], firstText: null,
});
const options = [{ label: "合并", recommended: true }];

async function open(t: ReturnType<typeof setup>) {
  t.subscribe(1, { topic: "chat", station: ST, thread: TH, session: null });
  t.subscribe(2, { topic: "decisions", workspace: "ws" });
  t.subscribe(3, { topic: "workspaceMarks" });
  await t.read();
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set({ topic: "workspace", workspace: "ws" }, { id: "ws", stations: [{ id: "st", name: "studio", last_seen: null, version: null }] });
  t.set({ topic: "prefs" }, {});
  t.set({ topic: "link", station: ST }, { state: "online" });
  await t.read();
}
const chat = (t: ReturnType<typeof setup>) => t.value(1);
const desk = (t: ReturnType<typeof setup>) => t.value(2);
const marks = (t: ReturnType<typeof setup>) => t.value(3).workspaces.ws;
const msg = (t: ReturnType<typeof setup>, seq: number) => chat(t).messages.find((m: J) => m.seq === seq);

const desk0 = (t: ReturnType<typeof setup>) => [desk(t).count, (desk(t).unread ?? []).length];

// (1) The user's real shape (their thread 19, also 24/9/3/5/7/10): a card (13) was answered by a message (14), the
// agent carried on and ended its next turn need_help with a plain post (16). The station gives the row `need` for 16.
test("a_need_without_a_card_is_a_text_card_in_the_chat_and_closes_everywhere_once_answered", async () => {
  const t = setup();
  await open(t);
  t.set({ topic: "threads", station: ST }, [threadOf(16)]);
  t.set({ topic: "thread", station: ST, thread: TH }, {
    first: 12, last: 16, thread: null, entries: [
      entry(12, "person", "咋还分成俩PR了"),
      entry(13, "agent", "要合并 #43 吗？", { declared: "need_help", card: { type: "options", options, assignee: "me@x.com" } }),
      entry(14, "person", "合并", { quotes: [{ author: "agent", text: "要合并 #43 吗？", comment: "", ts: "13.0", role: "agent" }] }),
      entry(15, "agent", "已经合进 main 了"),
      entry(16, "agent", "测试版 0.1.2191 已经发出来了 …… 更新后请在真实聊天里试一下", { declared: "need_help" }),
    ],
  });
  const row = baseRow({
    agents: [agent({ lastTurn: needHelp("更新到测试版 0.1.2191，确认复制的是原图") })],
    need: { seq: 16, message: said(16, "agent", "测试版 0.1.2191 已经发出来了 …… 更新后请在真实聊天里试一下"), before: [said(14, "person", "合并"), said(15, "agent", "已经合进 main 了")] },
  });
  t.set({ topic: "chatRows", station: ST }, [row]);
  await t.read();

  // The chat: the card at 13 reads as answered; the post at 16 is an open text card (written to in the composer), as
  // the 奏 page draws it, and the chat's open ask.
  assert.deepEqual([msg(t, 13).decision.resolved, msg(t, 13).decision.chosen], [true, "合并"]);
  assert.deepEqual([msg(t, 16).card, msg(t, 16).decision, msg(t, 16).options], [{ type: "text", assigneeText: "需要你决策", yours: true }, { resolved: false }, undefined]);
  assert.deepEqual([chat(t).decision.seq, chat(t).decision.card.type], [16, "text"]);
  assert.deepEqual(desk(t).items.map((i: J) => [i.seq, i.card.type]), [[16, "text"]]);
  // Row columns and marks: it asks, the 奏 page lists it; counted once, as an open ask.
  assert.deepEqual([chatDerive.asks(row), chatDerive.desk!(row), chatDerive.tone(row)], [true, true, null]);
  assert.deepEqual([marks(t).decisions, marks(t).wait, marks(t).unread, marks(t).alert], [1, 1, 0, 0]);

  // Answered from the composer: closed at once in the chat, on the 奏 page and in the counts.
  t.views.outboxAdd(ST, TH, { text: "试过了，是原图", attachments: [], quotes: [] });
  await t.read();
  assert.deepEqual([msg(t, 16).card, msg(t, 16).decision, chat(t).decision], [undefined, undefined, undefined]);
  assert.deepEqual(desk0(t), [0, 0]);
  assert.deepEqual([marks(t).decisions, marks(t).wait], [undefined, undefined]);
});

// (2) Sent from the composer while a card waits (not picked): the outbox answers it at once for the chat, the 奏 page
// and every count, before the station's row comes back.
test("a_message_sent_while_a_card_waits_clears_it_everywhere_at_once", async () => {
  const t = setup();
  await open(t);
  t.set({ topic: "threads", station: ST }, [threadOf(5)]);
  t.set({ topic: "thread", station: ST, thread: TH }, {
    first: 4, last: 5, thread: null, entries: [entry(4, "person", "看看 CI"), entry(5, "agent", "CI 全绿，要合并吗？", { declared: "need_help", card: { type: "options", options } })],
  });
  const card = { type: "options", options };
  const asking = baseRow({
    agents: [agent({ lastTurn: needHelp("等你决定要不要合并", { thread: TH, seq: 5, ts: "5.0" }) })],
    card: { seq: 5, card, message: { ...said(5, "agent", "CI 全绿，要合并吗？"), card, options }, before: [] },
    decision: { seq: 5, options, message: { ...said(5, "agent", "CI 全绿，要合并吗？"), options }, before: [] },
  });
  t.set({ topic: "chatRows", station: ST }, [asking]);
  await t.read();
  assert.equal(msg(t, 5).decision.resolved, false);
  assert.deepEqual([desk(t).count, marks(t).decisions, marks(t).wait], [1, 1, 1]);

  t.views.outboxAdd(ST, TH, { text: "先别合，把 changelog 也改一下", attachments: [], quotes: [] });
  await t.read();
  assert.equal(msg(t, 5).decision.resolved, true);
  assert.equal(chat(t).decision, undefined);
  assert.equal(desk(t).count, 0);
  assert.deepEqual([marks(t).decisions, marks(t).wait], [undefined, undefined]);

  // The station has the message: card gone, the agent queued.
  t.set({ topic: "chatRows", station: ST }, [baseRow({ agents: [agent({ pending: 1, lastTurn: needHelp("等你决定要不要合并", { thread: TH, seq: 5, ts: "5.0" }) })] })]);
  await t.read();
  assert.deepEqual([desk(t).count, marks(t).wait], [0, undefined]);
});

// (3) What the viewer has nothing open in is not counted: a need they dismissed, a card someone else decides, an agent
// that ended need_help with no card or need on its row.
test("a_dismissed_ask_someone_elses_or_a_bare_need_help_is_not_counted", async () => {
  const t = setup();
  await open(t);
  const dismissed = baseRow({
    agents: [agent({ lastTurn: needHelp("等 review") })],
    need: { seq: 9, message: said(9, "agent", "PR 等 review"), before: [], dismissed: true },
  });
  t.set({ topic: "chatRows", station: ST }, [dismissed]);
  await t.read();
  assert.equal(desk(t).count, 0);
  assert.deepEqual([marks(t).decisions, marks(t).wait, marks(t).tone], [undefined, undefined, undefined]);
  assert.deepEqual([chatDerive.asks(dismissed), chatDerive.tone(dismissed)], [false, null]);

  const card = { type: "options", options, assignee: "other@x.com" };
  const theirs = baseRow({
    agents: [agent({ lastTurn: needHelp("等小王决定") })],
    card: { seq: 9, card, message: { ...said(9, "agent", "合吗？"), card }, before: [] },
  });
  t.set({ topic: "chatRows", station: ST }, [theirs]);
  await t.read();
  assert.equal(desk(t).count, 0);
  // Drawn as theirs to answer: named, not the viewer's.
  const shown = { ...card };
  decisions.labelAssignee(shown, { id: "me@x.com", email: "me@x.com" }, [{ email: "other@x.com", name: "小王" }], me);
  assert.deepEqual([(shown as J).yours, (shown as J).deciderName, (shown as J).assigneeText], [undefined, "小王", "需要小王决策"]);
  assert.deepEqual([marks(t).decisions, marks(t).wait], [undefined, undefined]);

  t.set({ topic: "chatRows", station: ST }, [baseRow({ agents: [agent({ lastTurn: needHelp("要 key") })] })]);
  await t.read();
  assert.deepEqual([desk(t).count, marks(t).decisions, marks(t).wait], [0, undefined, undefined]);
});

// (4) The workspace's counts are the 奏 list's groups, each chat once: 要你决定 and 稍后 (`decisions`), 有新消息
// (`unread`: the viewer's chats, their agents done, nothing open for them); a failed one stays `alert`.
test("the_workspace_counts_are_the_decisions_lists_groups", async () => {
  const t = setup();
  await open(t);
  const text = { type: "text" };
  const asks = (id: string, th: number, patch: J = {}): J => baseRow({
    id, session: id, thread: th, title: id,
    card: { seq: 3, card: { ...text, assignee: "me@x.com" }, message: { ...said(3, "agent", `${id} 要 key`), thread: th, card: text }, before: [] }, ...patch,
  });
  const plain = (id: string, th: number, patch: J = {}): J => baseRow({ id, session: id, thread: th, title: id, ...patch });
  const done = { lastTurn: { kind: "input", outcome: "completed", declared: "final", ending: "all_done", startedAt: 1, endedAt: 2 } };
  const rows = [
    asks("ask", 31, { unread: true }),
    asks("later", 32),
    plain("news", 33, { unread: true, agents: [agent(done)], last: { seq: 4, text: "做完了\n细节", authorKind: "agent" }, lastActiveAt: 9 }),
    plain("busy", 34, { unread: true, agents: [agent({ process: "running" })] }),
    plain("failed", 35, { unread: true, agents: [agent({ lastTurn: { kind: "input", outcome: "failed", startedAt: 1, endedAt: 2 } })] }),
    plain("others", 36, { unread: true, mine: false, agents: [agent(done)] }),
  ];
  t.set({ topic: "prefs" }, { decisionsDeferred: { [decisions.deferralKey(ST, 32, 3)]: 5 } });
  t.set({ topic: "chatRows", station: ST }, rows);
  await t.read();
  const d = desk(t);
  assert.deepEqual(d.items.map((i: J) => [i.session, i.deferred ?? false]), [["ask", false], ["later", true]]);
  assert.deepEqual(d.unread.map((u: J) => [u.session, u.thread, u.title, u.line]), [["news", 33, "news", "做完了 细节"]]);
  const m = marks(t);
  assert.deepEqual([m.decisions, m.unread, m.alert], [d.count, d.unread.length, 1]);
  assert.equal(m.label, "1 个需要处理 · 2 个在等你 · 1 个有新消息");

  // Read, it is not new any more.
  t.set({ topic: "chatRows", station: ST }, rows.map((r) => (r.id === "news" ? { ...r, unread: false } : r)));
  await t.read();
  assert.deepEqual([desk(t).unread.length, marks(t).unread], [0, 0]);
});
