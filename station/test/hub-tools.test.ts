// The agents' tools (src/tools/chat.ts, slack.ts, adb.ts, feedback.ts) on the hub: their definitions, and
// what they do (ported from the Rust station's hub tests): posts, cards, states and what they are about, history, other
// chats, session_send, slack_api, files, titles, the archive suggestion after all_done.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { constants } from "node:sqlite";
import type { AddressInfo } from "node:net";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { test } from "node:test";
import { cardArg, optionsArg } from "../src/sessions/args.ts";
import { fingerprint } from "../src/sessions/decision.ts";
import type { CardPage } from "../src/logins/index.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { fromPeer, sender } from "../src/sessions/messages.ts";
import { handedOf } from "../src/store/rows.ts";
import { DecisionSessionsUnavailable } from "../src/store/legacy-decision-session.ts";
import { CREATE, CREATE_PRESET, NOTICE, createForPeer, noticeForPeer } from "../src/sessions/opened.ts";
import { presetCopyOf } from "../src/sessions/presets.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { forPeer } from "../src/sessions/others.ts";
import { makeStore } from "../src/read/store.ts";
import { chats, untitled } from "../src/read/views.ts";
import { FETCHED, fileForPeer, putForPeer } from "../src/sessions/peer-files.ts";
import { packWorkspaceIf } from "../src/sessions/archive.ts";
import { roomOf } from "../src/sessions/footprint.ts";
import { claudeProject } from "../src/read/transcript.ts";
import { Refused } from "../src/sessions/neighbours.ts";
import { archive, newSession, say as sayIn } from "../src/sessions/lifecycle.ts";
import { review, reviewUndecided, startReview } from "../src/sessions/review.ts";
import { cleanTitle, nameChat } from "../src/sessions/titles.ts";
import { adbTools } from "../src/adb/tool.ts";
import { archiveTools } from "../src/tools/archive.ts";
import { chatTools } from "../src/tools/chat.ts";
import { feedbackTools } from "../src/tools/feedback.ts";
import { remoteTools } from "../src/tools/remote.ts";
import type { Remote } from "../src/jobs/remote.ts";
import { DEFAULT_POLICY } from "../src/sessions/archive-policy.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Rig, matches, message, reply, say, settle } from "./hub-fakes.ts";

type Json = any;

// ── the definitions ──

test("every tool has a name, a description and an object's input schema; the chat tools in their order", () => {
  const r = new Rig();
  const ours = [...chatTools(r.hub), ...archiveTools(r.hub), ...remoteTools({} as Remote), ...adbTools(() => []), ...feedbackTools(r.store, () => null, () => null)];
  assert.deepEqual(
    chatTools(r.hub).map((t) => t.name),
    ["chat_post", "slack_api", "chat_state", "chat_leave", "chat_history", "chat_list", "chat_read", "session_send", "chat_create", "chat_archive", "session_history"],
  );
  assert.equal(new Set(ours.map((t) => t.name)).size, ours.length, "no name twice");
  for (const tool of ours) {
    assert.match(tool.name, /^[a-z_]+$/);
    assert.ok(tool.description.length > 0, tool.name);
    assert.equal((tool.inputSchema as Json).type, "object", tool.name);
    for (const required of (tool.inputSchema as Json).required ?? []) assert.ok(required in (tool.inputSchema as Json).properties, `${tool.name}: ${required}`);
  }
  void r.close();
});

// ── posts ──

test("chat_post with kind final posts and settles the turn without a nudge", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  // "final", from a session whose instructions are from before all_done, is all_done.
  assert.equal(await r.call(key, "chat_post", { to, text: "**done**", kind: "final" }), `Posted to ${to}, and recorded state all_done.`);
  r.claude.last().complete();
  await settle();
  assert.equal(r.claude.last().prompts.length, 1);
  assert.deepEqual(r.chat.posts, [[{ channel: "C1", threadTs: m.threadTs }, "**done**"]]);
  await r.close();
});

test("the agent's posts are recorded in the thread, and chat_history shows them as its own", async () => {
  const r = new Rig();
  const m = say("<@UBOT> look");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  await r.call(key, "chat_post", { to, text: "looking", kind: "block" });
  const said = r.said(r.thread("C1", m.threadTs).id);
  assert.deepEqual([said[0]!.authorKind, said[1]!.authorKind, said[1]!.author, said[1]!.declared], ["person", "agent", key, "need_help"]);
  assert.equal(r.store.pendingMessages(key).length, 0, "an agent's own post is not delivered back to it");
  const history = await r.call(key, "chat_history", { to });
  assert.ok(matches(history, ['from="U1" ts="', '">\n<@UBOT> look', 'from="you" ts="', '">\nlooking']), history);
  await r.close();
});

test("chat_leave stops a thread's messages reaching its agent until someone mentions it there again", async () => {
  const r = new Rig();
  const m = say("<@UBOT> look");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  await r.call(key, "chat_post", { to, text: "好，这个 thread 我不再看了，需要时再 @ 我", kind: "all_done", done: "已退出这个 thread" });
  assert.ok((await r.call(key, "chat_leave", { to })).startsWith(`Left ${to}:`));
  r.claude.last().complete();
  await settle();
  // The thread is told it left, in place of done.
  assert.deepEqual(r.chat.stands.filter(([t]) => t === to).at(-1)?.[1], { kind: "left", words: null });
  // Chatter there is still recorded, but no longer handed to it.
  await r.accept({ ...say("we can take it from here", { addressed: false }), threadTs: m.threadTs });
  await settle();
  assert.equal(r.said(r.thread("C1", m.threadTs).id).at(-1)!.text, "we can take it from here");
  assert.equal(r.store.pendingMessages(key).length, 0);
  assert.equal(r.claude.last().prompts.length, 1);
  // It still reads the thread and posts there.
  assert.ok((await r.call(key, "chat_history", { to })).includes("we can take it from here"));
  // A mention brings it back, and what follows reaches it again.
  await r.accept({ ...say("<@UBOT> one more thing"), threadTs: m.threadTs });
  await settle();
  assert.equal(r.claude.last().prompts.length, 2);
  assert.ok(r.claude.last().prompts[1]!.includes("one more thing"));
  await r.call(key, "chat_post", { to, text: "ok", kind: "all_done", done: "回答了他补充的问题，见 ok 这条回复" });
  r.claude.last().complete();
  await settle();
  // Back: its end says done again.
  assert.equal(r.chat.stands.filter(([t]) => t === to).at(-1)?.[1]?.kind, "done");
  await r.accept({ ...say("and this", { addressed: false }), threadTs: m.threadTs });
  await settle();
  assert.equal(r.claude.last().prompts.length, 3);
  await r.close();
});

test("chat_leave refuses a still.fail chat", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, { runtime: "claude" as const, createdBy: "ada@x.com" });
  assert.ok((await r.refused(key, "chat_leave", { to: `CHAT/${thread.threadTs}` })).includes("cannot be left"));
  await r.close();
});

test("an agent reads another session's chat by its link or address, and finds it in the list", async () => {
  const r = new Rig();
  const [a, b] = [say("<@UBOT> look at the build"), say("<@UBOT> what did the other chat find?")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  const toA = `C1/${a.threadTs}`;
  await r.call(keyA, "chat_post", { to: toA, text: "the build is green" });
  // Not one of B's conversations, yet B reads it: by its address, by its chat's link, by its session key.
  const link = `https://ember.test/w/ws/s/st/chats/${keyA.replaceAll(":", "%3A")}`;
  for (const chat of [toA, link, keyA]) {
    const read = await r.call(keyB, "chat_read", { chat });
    assert.ok(matches(read, [`Conversation ${toA}; its agents: ${keyA}.`, 'from="U1"', "look at the build", `from="${keyA}" bot`, "the build is green"]), read);
  }
  const listed = await r.call(keyB, "chat_list", { query: "BUILD" });
  assert.ok(matches(listed, [`- ${toA} (Slack thread)`, `agents: ${keyA};`, "the build is green"]), listed);
  assert.ok(!listed.includes(b.threadTs), listed);
  const mine = await r.call(keyB, "chat_list", {});
  assert.ok(mine.includes(`${keyB} (you)`), mine);
  // Read by the readers where there are (agents.ts): the same list, the store not asked on the main thread.
  const store = r.hub.store.listThreads("", null, null);
  r.hub.threadList = async () => JSON.parse(JSON.stringify(store));
  const listThreads = r.hub.store.listThreads;
  r.hub.store.listThreads = () => assert.fail("listed on the main thread");
  assert.equal(await r.call(keyB, "chat_list", {}), mine);
  r.hub.store.listThreads = listThreads;
  assert.equal(await r.call(keyB, "session_history", { chat: toA }), `Session ${keyA} has no execution history yet.`);
  assert.ok((await r.refused(keyB, "chat_read", { chat: "https://ember.test/o/ws/st/nope" })).includes("not on this station"));
  assert.ok((await r.refused(keyB, "chat_read", { chat: "C9/1.000001" })).includes("no conversation C9/1.000001"));
  await r.close();
});

test("session_history reads a session's transcript, numbered as the pages number it", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const row = r.session(key);
  // Where Claude Code writes the session it runs: the project of its working directory.
  const dir = join(r.config.profiles[0]!.home, "projects", claudeProject(row.cwd ?? row.workspace)!);
  const { mkdirSync } = await import("node:fs");
  mkdirSync(dir, { recursive: true });
  const line = (text: string, id: string) => JSON.stringify({ type: "assistant", timestamp: "2026-09-26T00:00:00Z", message: { id, content: [{ type: "text", text }] } });
  writeFileSync(join(dir, `${row.runtimeSessionId}.jsonl`), `${line("one", "m1")}\n${line("two", "m2")}\n`);
  const history = await r.call(key, "session_history", { chat: key, max_chars: 100 });
  assert.ok(matches(history, [`Session ${key} (claude, opus): entries #0–#1 of 2.`, "#0 ", "one", "#1 ", "two"]), history);
  await r.close();
});

test("chat_state refuses kinds it does not know", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  assert.ok((await r.refused(sessionKey("cl", "C1", m.threadTs), "chat_state", { kind: "wait" })).includes('"all_done" or "need_human" (or "waiting"'));
  await settle();
  await r.close();
});

test("chat_post and chat_history need an explicit thread of this session", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.ok(matches(await r.refused(key, "chat_post", { text: "hi" }), ["to is required", "C1/"]));
  assert.ok((await r.refused(key, "chat_post", { to: "C1", text: "hi" })).includes("CHANNEL/THREAD_TS"));
  assert.ok((await r.refused(key, "chat_post", { to: "C9/1.1", text: "hi" })).includes("not a conversation of this session"));
  assert.ok((await r.refused(key, "chat_history", {})).includes("to is required"));
  assert.deepEqual(r.chat.texts(), []);
  await r.close();
});

const web = (createdBy = "ada@x.com") => ({ runtime: "claude" as const, createdBy });

test("a post carries a card, kept with it and checked", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web());
  sayIn(r.hub, thread.id, "ada@x.com", "fix the spacing");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const kept = () => {
    const n = r.said(thread.id).at(-1)!.n;
    return r.store.entriesBetween(thread.id, n, n)[0]!;
  };
  const options = [
    { label: " 按今天累计 ", detail: "重连不清零，零点归零", recommended: true },
    { label: "先不改", detail: "", recommended: false },
  ];
  const shown = [{ label: "按今天累计", detail: "重连不清零，零点归零", recommended: true }, { label: "先不改" }];
  // An options card, with the turn ending need_help: the card is the message's, the state the turn's.
  let said = await r.call(key, "chat_post", { to, text: "「共」改成按今天累计吗？", kind: "need_help", need: "选统计口径", card: { type: "options", options } });
  assert.ok(said.startsWith(`Posted to ${to}, and recorded state need_human. People can pick, numbered as the card shows them: 1. 先不改; 2. 按今天累计 (recommended);`), said);
  let entry = kept();
  assert.deepEqual(entry.card, { type: "options", options: shown });
  assert.deepEqual(entry.options, shown, "kept as options too: what stations and clients from before cards read");
  assert.equal(entry.declared, "need_help");
  // A text card, on a progress post (no kind): any post may carry one.
  said = await r.call(key, "chat_post", { to, text: "测试 key 是多少？", card: { type: "text", placeholder: " sk_test_… " } });
  assert.ok(said.startsWith(`Posted to ${to}. People can write their answer`), said);
  entry = kept();
  assert.deepEqual([entry.card, entry.options, entry.declared], [{ type: "text", placeholder: "sk_test_…" }, undefined, null]);
  await r.call(key, "chat_post", { to, text: "名字？", card: '{"type": "text"}' });
  assert.deepEqual(kept().card, { type: "text" }, "as JSON text, from a runtime whose tool list is from before cards");
  // need_decision, from before cards: an options card, the turn need_help needing what it asks.
  said = await r.call(key, "chat_post", { to, text: "**「共」改成按今天累计吗？**\n细节", kind: "need_decision", options });
  assert.ok(said.includes("recorded state need_human. People can pick"), said);
  assert.deepEqual([kept().card, kept().declared], [{ type: "options", options: shown }, "need_help"]);
  r.claude.last().complete();
  await settle();
  assert.equal(r.store.lastTurn(key)!.need, "「共」改成按今天累计吗？", "it needs what the post asks");
  // Options as JSON text, asking with block; a bare phrase is a label.
  said = await r.call(key, "chat_post", { to, text: "选哪个？", kind: "block", options: '["A", {"label": "B"}]' });
  assert.ok(said.includes("recorded state need_human."), said);
  assert.deepEqual(kept().options, [{ label: "A" }, { label: "B" }]);
  // Options without a kind: an options card all the same.
  await r.call(key, "chat_post", { to, text: "顺便：哪个？", options: [{ label: "A" }] });
  assert.deepEqual(kept().card, { type: "options", options: [{ label: "A" }] });
  // A post without a card keeps none.
  await r.call(key, "chat_post", { to, text: "进度" });
  assert.deepEqual([kept().card, kept().options], [undefined, undefined]);
  const refused = (args: Json) => r.refused(key, "chat_post", args);
  const one = [{ label: "A" }];
  assert.ok((await refused({ to, text: "x", card: { type: "poll" } })).includes('unknown card type "poll": the types known are options, text, login'));
  assert.ok((await refused({ to, text: "x", card: {} })).includes("one of options, text, login"));
  assert.ok((await refused({ to, text: "x", card: ["A"] })).includes("card must be an object"));
  assert.ok((await refused({ to, text: "x", card: { type: "options" } })).includes("an options card has options"));
  assert.ok((await refused({ to, text: "x", card: { type: "options", options: one }, options: one })).includes("not also as options"));
  assert.ok((await refused({ to, text: "x", card: { type: "text", placeholder: "字".repeat(81) } })).includes("at most 80"));
  assert.ok((await refused({ to, text: "x", kind: "need_help", card: { type: "text" } })).includes("need is required"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision" })).includes("carries options"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: [] })).includes("1 to 6"));
  const seven = Array.from({ length: 7 }, (_, i) => ({ label: `选项${i}` }));
  assert.ok((await refused({ to, text: "x", card: { type: "options", options: seven } })).includes("1 to 6"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: [{ label: " " }] })).includes("label is empty"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: [{ label: "A" }, { label: "A" }] })).includes("repeats"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: [{ label: "A", recommended: true }, { label: "B", recommended: true }] })).includes("only one"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: { label: "A" } })).includes("must be an array"));
  assert.ok((await refused({ to, text: "x", kind: "need_decision", options: "not json" })).includes("must be an array"));
  assert.ok((await refused({ to, files: [], card: { type: "text" } })).includes("text is empty"));
  await r.close();
});

test("answering a clarification cannot silently restore need_human", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web());
  sayIn(r.hub, thread.id, "ada@x.com", "改一下");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  await r.call(key, "chat_post", { to, text: "可以合并吗？", card: { type: "options", options: [{ label: "合并" }] } });
  assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "确认合并" }), "Recorded state need_human.");
  r.claude.last().complete();
  await settle();
  sayIn(r.hub, thread.id, "ada@x.com", "跟随订阅就是标准吧");
  await settle();
  const person = r.said(thread.id).at(-1)!.ts;
  await r.call(key, "chat_post", { to, text: "默认情况下是标准。" });
  assert.ok((await r.refused(key, "chat_state", { kind: "need_human", need: "等待确认是否合并" })).includes("requires a visible question"));
  assert.ok((await r.refused(key, "chat_state", { kind: "need_human", need: "确认合并", about: person })).includes("your visible question"));
  // A visible plain-text request works without forcing a new card.
  await r.call(key, "chat_post", { to, text: "还需要你确认：这版可以合并吗？", kind: "need_human", need: "确认合并" });
  await r.close();
});

test("a clarification tells the agent its card stopped waiting, and it cannot reuse that card as the wait", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    const posted = await r.call(key, "chat_post", { to, text: "可以合并吗？", kind: "need_human", need: "确认合并", card: { type: "options", options: [{ label: "合并" }] } });
    const card = r.said(thread.id).at(-1)!;
    assert.ok(posted.includes(card.ts), "the agent can identify and withdraw the card it posted");
    assert.ok((await r.call(key, "chat_history", { to })).includes("Answer card: pending"));
    r.claude.last().complete();
    await settle();
    sayIn(r.hub, thread.id, "ada@x.com", "测试过了吗？");
    await settle();
    const prompt = r.claude.last().prompts.at(-1)!;
    assert.ok(prompt.includes(card.ts) && prompt.includes("no longer pending"), prompt);
    assert.ok(prompt.includes("not necessarily") && prompt.includes("new card"), prompt);
    assert.equal(r.store.pendingCard(thread.id), null);
    const history = await r.call(key, "chat_history", { to });
    assert.ok(history.includes("Answer card: no longer pending") && history.includes("合并"), history);
    await r.call(key, "chat_post", { to, text: "测试通过了。" });
    assert.ok((await r.refused(key, "chat_state", { kind: "need_human", need: "确认合并", about: card.ts })).includes("no longer pending"));
    assert.ok((await r.refused(key, "chat_post", { to, text: "等你确认。", kind: "need_human", need: "确认合并", about: card.ts })).includes("no longer pending"));
    await r.call(key, "chat_post", { to, text: "测试通过了，可以合并吗？", card: { type: "options", options: [{ label: "合并" }] } });
    assert.ok(r.store.pendingCard(thread.id) !== null, "a fresh question is actionable");
  } finally {
    await r.close();
  }
});

test("a newer card remains pending when an unread clarification ended the earlier card", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    const agent = r.claude.last();
    agent.unsteerable = true;
    await r.call(key, "chat_post", { to, text: "第一版可以合并吗？", card: { type: "options", options: [{ label: "合并" }] } });
    const old = r.said(thread.id).at(-1)!;
    sayIn(r.hub, thread.id, "ada@x.com", "测试过了吗？");
    const held = await r.call(key, "chat_post", { to, text: "第二版可以合并吗？", card: { type: "options", options: [{ label: "合并第二版" }] } });
    assert.ok(held.startsWith("Not posted"), held);
    agent.complete();
    await settle();
    const prompt = agent.prompts.at(-1)!;
    assert.ok(prompt.includes(old.ts) && prompt.includes("no longer pending"), prompt);
    await r.call(key, "chat_post", { to, send: held.match(/Held as (held-\d+)/)![1]! });
    const current = r.said(thread.id).at(-1)!;
    assert.equal(current.text, "第二版可以合并吗？");
    assert.equal(r.store.pendingCard(thread.id)?.[0].n, current.n);
    const history = await r.call(key, "chat_history", { to });
    assert.ok(history.includes("Answer card: no longer pending") && history.includes("Answer card: pending"), history);
  } finally {
    await r.close();
  }
});

test("a card withdrawn before a message is not attributed to that message", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    await r.call(key, "chat_post", { to, text: "可以合并吗？", card: { type: "options", options: [{ label: "合并" }] } });
    const card = r.said(thread.id).at(-1)!;
    await r.call(key, "chat_post", { to, withdraw: card.ts });
    sayIn(r.hub, thread.id, "ada@x.com", "测试过了吗？");
    await settle();
    const prompt = r.claude.last().steers.at(-1)!;
    assert.ok(!prompt.includes("<card-state"), prompt);
  } finally {
    await r.close();
  }
});

test("a choice that closes a card is told to its agent once, before what it is next handed, as an earlier choice", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    await r.call(key, "chat_post", { to, text: "要部署吗？", kind: "need_human", need: "选是否部署",
      card: { type: "options", options: [{ label: "部署" }, { label: "不需要部署", action: "close" }] } });
    const card = r.said(thread.id).at(-1)!;
    r.claude.last().complete();
    await settle();
    const handed = () => r.claude.sessions.flatMap((s) => [...s.prompts, ...s.steers]);
    const before = handed().length;
    assert.equal(r.store.closeCard("ada@x.com", thread.id, card.n, "不需要部署"), true);
    await settle();
    assert.equal(handed().length, before, "the choice itself sends nothing and wakes no one");
    assert.deepEqual(r.store.untoldCardChoices(key).map((c) => [c.ts, c.by, c.option, c.question]), [[card.ts, "ada@x.com", "不需要部署", "要部署吗？"]]);

    sayIn(r.hub, thread.id, "ada@x.com", "另外看下日志");
    await settle();
    const prompt = handed().at(-1)!;
    assert.ok(prompt.includes(`<card-choice thread="${to}" card="${card.ts}" by="ada@x.com (ada@x.com)" at="`), prompt);
    assert.ok(prompt.includes("Asked: 要部署吗？\nChosen: 不需要部署\n</card-choice>"), prompt);
    assert.ok(prompt.includes("not about them unless it says so"), prompt);
    assert.ok(prompt.indexOf("<card-choice") < prompt.indexOf("另外看下日志"), "the earlier choice comes before the new message");
    assert.ok(!prompt.includes("<card-state"), prompt);
    assert.deepEqual(r.store.untoldCardChoices(key), []);

    r.claude.last().complete();
    await settle();
    sayIn(r.hub, thread.id, "ada@x.com", "好了吗");
    await settle();
    assert.ok(!handed().at(-1)!.includes("<card-choice"), "told once");
    const history = await r.call(key, "chat_history", { to });
    assert.ok(history.includes('Answer card: no longer pending; ada@x.com (ada@x.com) chose "不需要部署", which closed it without a message;'), history);
  } finally {
    await r.close();
  }
});

test("a choice that closes a card comes with a station notice too, and waits when the notice cannot be handed", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    const agent = r.claude.last();
    await r.call(key, "chat_post", { to, text: "CI 过了要合并吗？", card: { type: "options", options: [{ label: "合并" }, { label: "先不合", action: "close" }] } });
    const card = r.said(thread.id).at(-1)!;
    // Chosen while the turn that asked still runs, and it takes no steer: nothing is told, nothing is lost.
    assert.equal(r.store.closeCard("ada@x.com", thread.id, card.n, "先不合"), true);
    agent.unsteerable = true;
    r.hub.notify(key, "the CI watch ended");
    await settle();
    assert.equal(r.store.untoldCardChoices(key).length, 1);
    agent.unsteerable = false;
    r.hub.notify(key, "the CI watch ended again");
    await settle();
    const steer = agent.steers.at(-1)!;
    assert.ok(steer.includes("Chosen: 先不合") && steer.indexOf("<card-choice") < steer.indexOf("the CI watch ended again"), steer);
    assert.deepEqual(r.store.untoldCardChoices(key), []);
  } finally {
    await r.close();
  }
});

test("a closed authorization card tells its agent how to reask the same request", async () => {
  for (const [extra, action] of [
    [{ vault: { request: "r_test" } }, 'secret_reask {request: "r_test"}'],
    [{ adb: { request: "p_test", reason: "check the screen" } }, 'phone_use {reason: "check the screen", reask: true}'],
    [{ signin: { site: "example.com" } }, 'sign_in {site: "example.com", reask: true}'],
  ] as const) {
    const r = new Rig();
    try {
      const [key, thread] = newSession(r.hub, web());
      sayIn(r.hub, thread.id, "ada@x.com", "做这个");
      await settle();
      r.store.insertMessage({ thread: thread.id, ts: r.hub.nextTs(), authorKind: "agent", author: key, text: "需要授权", card: { type: "options", options: [{ label: "允许" }], ...extra } });
      sayIn(r.hub, thread.id, "ada@x.com", "为什么需要？");
      await settle();
      const prompt = r.claude.last().steers.at(-1)!;
      assert.ok(prompt.includes("no longer pending") && prompt.includes(action), prompt);
    } finally {
      await r.close();
    }
  }
});

test("a message the agent had not read holds a card back; sent after it, the card is pending", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, web());
    const to = `CHAT/${thread.threadTs}`;
    sayIn(r.hub, thread.id, "ada@x.com", "做这个");
    await settle();
    const agent = r.claude.last();
    agent.unsteerable = true;
    sayIn(r.hub, thread.id, "ada@x.com", "先告诉我测试结果");
    const held = await r.call(key, "chat_post", { to, text: "可以合并吗？", card: { type: "options", options: [{ label: "合并" }] } });
    assert.ok(held.startsWith("Not posted"), held);
    assert.equal(r.store.pendingCard(thread.id), null, "held: no card yet");
    agent.complete();
    await settle();
    assert.ok(agent.prompts.at(-1)!.includes("先告诉我测试结果"));
    await r.call(key, "chat_post", { to, send: held.match(/Held as (held-\d+)/)![1]! });
    assert.equal(r.store.pendingCard(thread.id)?.[0].ts, r.said(thread.id).at(-1)!.ts);
  } finally {
    await r.close();
  }
});

test("a state says which message it is about, the pending card by default", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web());
  sayIn(r.hub, thread.id, "ada@x.com", "上线吧");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const about = () => r.store.lastTurn(key)!.about;
  // need_help after a card: about the card, by default.
  await r.call(key, "chat_post", { to, text: "合吗？", card: { type: "options", options: [{ label: "合" }] } });
  const card = r.said(thread.id).at(-1)!;
  await r.call(key, "chat_post", { to, text: "等你看一下", kind: "need_help", need: "决定合不合" });
  r.claude.last().complete();
  await settle();
  assert.deepEqual(about(), { thread: thread.id, seq: card.n, ts: card.ts });
  // all_done about the message with the result, given by its ts; with chat_state too.
  sayIn(r.hub, thread.id, "ada@x.com", "合");
  await settle();
  await r.call(key, "chat_post", { to, text: "已合进 main" });
  const result = r.said(thread.id).at(-1)!;
  assert.equal(await r.call(key, "chat_state", { kind: "all_done", done: "已合进 main 82f108a5", about: result.ts }), "Recorded state all_done.");
  r.claude.last().complete();
  await settle();
  assert.deepEqual(about(), { thread: thread.id, seq: result.n, ts: result.ts });
  // waiting about the message saying what was started; need_help with no card waiting is about nothing.
  sayIn(r.hub, thread.id, "ada@x.com", "再跑一遍测试");
  await settle();
  await r.call(key, "chat_post", { to, text: "测试开始跑了" });
  const started = r.said(thread.id).at(-1)!;
  await r.call(key, "chat_state", { kind: "waiting", seconds: 60, for: "测试跑完", about: started.ts });
  r.claude.last().complete();
  await settle();
  assert.equal(about()?.seq, started.n);
  sayIn(r.hub, thread.id, "ada@x.com", "怎样了");
  await settle();
  await r.call(key, "chat_post", { to, text: "卡住了", kind: "need_help", need: "要 key" });
  r.claude.last().complete();
  await settle();
  assert.equal(about(), null, "no card waiting, none given");
  // A ts not in the chat, or about with no kind: refused.
  sayIn(r.hub, thread.id, "ada@x.com", "给你");
  await settle();
  assert.ok((await r.refused(key, "chat_post", { to, text: "x", kind: "all_done", done: "已合进 main 82f108a5", about: "1.000001" })).includes("about must be the ts of a message"));
  assert.ok((await r.refused(key, "chat_state", { kind: "all_done", done: "已合进 main 82f108a5", about: "1.000001" })).includes("about must be the ts of a message"));
  assert.ok((await r.refused(key, "chat_post", { to, text: "x", about: started.ts })).includes("about goes with kind"));
  await r.close();
});

test("options are refused where the chat shows no cards", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.ok((await r.refused(key, "chat_post", { to: `C1/${m.threadTs}`, text: "选哪个？", kind: "need_decision", options: [{ label: "A" }] })).includes("cards (options, a text field) are not shown here"));
  assert.ok((await r.refused(key, "chat_post", { to: `C1/${m.threadTs}`, text: "key？", card: { type: "text" } })).includes("cards (options, a text field) are not shown here"));
  await r.close();
});

test("a card is pending until a person writes, and a newer one replaces it", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web());
  sayIn(r.hub, thread.id, "ada@x.com", "fix the spacing");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const pending = () => {
    const p = r.store.pendingCard(thread.id);
    return p ? [p[0].n, p[1]] : null;
  };
  assert.equal(pending(), null);
  // Help asked for asks nothing to pick.
  await r.call(key, "chat_post", { to, text: "要 key", kind: "need_help", need: "要 Stripe 的测试 key" });
  assert.equal(pending(), null);
  await r.call(key, "chat_post", { to, text: "合吗？", kind: "need_decision", options: [{ label: "合" }] });
  const first = r.said(thread.id).at(-1)!.n;
  assert.deepEqual(pending(), [first, { type: "options", options: [{ label: "合" }] }]);
  // The agent saying more without options leaves it pending; only people answer it.
  await r.call(key, "chat_post", { to, text: "顺便说一下进度" });
  assert.equal(pending()?.[0], first);
  // A newer one replaces it.
  await r.call(key, "chat_post", { to, text: "还是先问这个：留哪个？", kind: "need_decision", options: [{ label: "留旧的" }, { label: "留新的" }] });
  const second = r.said(thread.id).at(-1)!.n;
  assert.equal(pending()?.[0], second);
  // Any person's message after it answers it, quoting it or not.
  sayIn(r.hub, thread.id, "bob@x.com", "都不要，换个思路");
  assert.equal(pending(), null);
  await settle();
  r.claude.last().reads();
  await r.call(key, "chat_post", { to, text: "那这样？", kind: "need_decision", options: [{ label: "好" }] });
  assert.ok(pending() !== null);
  // A text card replaces it as well, on a post with no kind.
  await r.call(key, "chat_post", { to, text: "域名填哪个？", card: { type: "text", placeholder: "example.com" } });
  const text = r.said(thread.id).at(-1)!.n;
  assert.deepEqual(pending(), [text, { type: "text", placeholder: "example.com" }]);
  sayIn(r.hub, thread.id, "ada@x.com", "still.fail");
  assert.equal(pending(), null);
  await settle();
  await r.close();
});

test("a turn ends all_done, needing a decision or help, or waiting, and the words from before still count", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  const last = () => r.store.lastTurn(key)!;
  // need_help says what is needed: kept with the turn; refused without it.
  assert.ok((await r.refused(key, "chat_post", { to, text: "卡住了", kind: "need_help" })).includes("need is required"));
  assert.equal(await r.call(key, "chat_post", { to, text: "卡住了", kind: "need_human", need: " 要 Stripe 的测试 key " }), `Posted to ${to}, and recorded state need_human.`);
  r.claude.last().complete();
  await settle();
  assert.deepEqual([last().declared, last().ending, last().need], ["block", "need_help", "要 Stripe 的测试 key"], "clients from before read block");
  assert.equal(r.claude.last().prompts.length, 1, "a state: not nudged");
  // need goes only with need_help; need_decision only posted, with options.
  await r.accept(reply(m, "9999.1", "给你 key"));
  await settle();
  assert.ok((await r.refused(key, "chat_state", { kind: "all_done", need: "x", done: "y" })).includes('only with kind "need_human"'));
  assert.ok((await r.refused(key, "chat_state", { kind: "all_done" })).includes("done is required"));
  // done is a reason people can trust, not the word done.
  for (const empty of ["已完成", " 完成。", "已完成", "Done!", "ok", "好了", "全部搞定"]) {
    assert.ok((await r.refused(key, "chat_state", { kind: "all_done", done: empty })).includes("done must say why nothing in the chat is left"), empty);
  }
  assert.ok((await r.refused(key, "chat_state", { kind: "need_help", need: "x", done: "y" })).includes('only with kind "all_done"'));
  assert.ok((await r.refused(key, "chat_state", { kind: "need_decision" })).includes("posted with chat_post"));
  assert.ok((await r.refused(key, "chat_state", { kind: "need_help" })).includes("need is required"));
  assert.ok((await r.refused(key, "chat_state", { kind: "done" })).includes("all_done"));
  assert.ok((await r.refused(key, "chat_state", { kind: "need_help", need: "确认一下要不要上线" })).includes("requires a visible question"));
  await r.call(key, "chat_post", { to, text: "确认一下要不要上线？" });
  const question = r.said(r.store.sessionThreads(key)[0]!.thread.id).at(-1)!.ts;
  assert.equal(await r.call(key, "chat_state", { kind: "need_help", need: "确认一下要不要上线", about: question }), "Recorded state need_human.");
  r.claude.last().complete();
  await settle();
  assert.deepEqual([last().ending, last().need], ["need_help", "确认一下要不要上线"]);
  // all_done says what the chat ends with, kept as need is.
  await r.accept(reply(m, "9999.2", "上了"));
  await settle();
  assert.equal(await r.call(key, "chat_state", { kind: "all_done", done: "已合并所有代码" }), "Recorded state all_done.");
  r.claude.last().complete();
  await settle();
  assert.deepEqual([last().ending, last().need], ["all_done", "已合并所有代码"]);
  // The words from before: block needs no need; final is all_done.
  await r.accept(reply(m, "9999.25", "上吧"));
  await settle();
  assert.equal(await r.call(key, "chat_state", { kind: "block" }), "Recorded state need_human.");
  r.claude.last().complete();
  await settle();
  assert.deepEqual([last().declared, last().ending, last().need], ["block", "need_help", null]);
  await r.accept(reply(m, "9999.3", "好了吗"));
  await settle();
  assert.equal(await r.call(key, "chat_state", { kind: "final" }), "Recorded state all_done.");
  r.claude.last().complete();
  await settle();
  assert.deepEqual([last().declared, last().ending], ["final", "all_done"]);
  assert.deepEqual(
    r.said(r.thread("C1", m.threadTs).id).flatMap((x) => x.declared ?? []),
    ["need_help"],
    "posts keep today's words",
  );
  await r.close();
});

test("a login card names its login, and closes for everyone as the login ends", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  const to = `CHAT/${thread.threadTs}`;
  const kept = () => {
    const n = r.said(thread.id).at(-1)!.n;
    return r.store.entriesBetween(thread.id, n, n)[0]!;
  };
  const said = await r.call(key, "chat_post", { to, text: "要在 orchard 上登录 GitHub", kind: "need_human", need: "登录 GitHub", card: { type: "login", login: "abc123", assignee: "a@x.com" } });
  assert.ok(said.includes("People finish the login from the card"), said);
  assert.deepEqual(kept().card, { type: "login", login: "abc123", assignee: "a@x.com" });
  assert.ok(r.store.pendingCard(thread.id) !== null);
  const refused = (args: Json) => r.refused(key, "chat_post", args);
  assert.ok((await refused({ to, text: "x", card: { type: "login" } })).includes("a login card names the login"));
  assert.ok((await refused({ to, text: "x", card: { type: "login", login: "a b" } })).includes("a login card names the login"));
  assert.ok((await refused({ to, text: "x", card: { type: "login", login: "abc", station: "orchard" } })).includes("card.station"));
  // Another login's end leaves it; its own closes it (nobody answered: withdrawn, as by its agent).
  assert.deepEqual(r.store.closeLoginCards("abc12"), []);
  assert.ok(r.store.pendingCard(thread.id) !== null);
  assert.deepEqual(r.store.closeLoginCards("abc123"), [key], "its agent: told the login ended");
  assert.equal(r.store.pendingCard(thread.id), null);
  assert.deepEqual(r.store.closeLoginCards("abc123"), [], "once");
  await r.close();
});

test("an agent can withdraw its own card without posting or finishing work", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  const to = `CHAT/${thread.threadTs}`;
  await r.call(key, "chat_post", { to, text: "保留吗？", card: { type: "text" } });
  const first = r.said(thread.id).at(-1)!;
  assert.ok(!r.store.withdrawCard("someone-else", thread.id, first.ts));
  await assert.rejects(r.call(key, "chat_post", { to, withdraw: first.ts, text: "混在一起" }));
  assert.ok(r.store.pendingCard(thread.id) !== null);
  for (let i = 0; i < 2; i++) await r.call(key, "chat_post", { to, withdraw: first.ts });
  assert.equal(r.store.pendingCard(thread.id), null);
  assert.equal(r.said(thread.id).length, 1, "no new message or deleted question");
  await r.call(key, "chat_post", { to, text: "另一个问题？", card: { type: "options", options: [{ label: "好" }] } });
  await r.call(key, "chat_post", { to, withdraw: first.ts });
  assert.ok(r.store.pendingCard(thread.id) !== null, "retry cannot withdraw the newer card");
  await r.close();
});

test("only explicit, valid option actions close silently; cards keep explicit assignees", () => {
  const parsed = optionsArg([{ label: "不需要部署", action: "close" }, { label: "不需要处理" }, { label: "部署", action: "reply" }])!;
  assert.equal(parsed[0].action, "close");
  assert.equal(parsed[1].action, undefined, "labels never imply silent closure");
  assert.equal(parsed[2].action, "reply");
  assert.throws(() => optionsArg([{ label: "不需要", action: "typo" }]));
  for (const base of [{ type: "text" }, { type: "options", options: [{ label: "好" }] }]) {
    assert.equal(cardArg(base, undefined).assignee, undefined);
    const card: Json = { ...base, assignee: " Owner@Example.com " };
    assert.equal(cardArg(card, undefined).assignee, "owner@example.com");
    for (const bad of ["小王", "", ["owner@example.com"], "a@b@c"]) {
      card.assignee = bad;
      assert.throws(() => cardArg(card, undefined));
    }
  }
});

// ── files ──

test("web posts deliver local file links, and refuse missing files before posting", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  const workspace = r.session(key).workspace;
  const source = join(workspace, "report.txt");
  writeFileSync(source, "original report");
  const to = `CHAT/${thread.threadTs}`;
  await r.call(key, "chat_post", { to, text: `Read [report](${source})` });
  const posted = r.said(thread.id).at(-1)!;
  assert.equal(posted.text, "Read [report](report%2Etxt)");
  assert.equal(posted.attachments.length, 1);
  assert.equal(posted.attachments[0]!.name, "report.txt");
  writeFileSync(source, "changed report");
  assert.equal(readFileSync(posted.attachments[0]!.path, "utf8"), "original report");
  const count = r.said(thread.id).length;
  assert.ok((await r.refused(key, "chat_post", { to, text: "[report](/tmp/stillfail-missing-file.txt)" })).includes("correct the path"));
  assert.equal(r.said(thread.id).length, count);
  await r.close();
});

test("files posted to Slack go into the thread; apps without files:write link to still.fail", async () => {
  const r = new Rig({ link: true });
  const m = say("<@UBOT> chart it");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  const workspace = r.session(key).workspace;
  for (const name of ["shot.png", "weather.html"]) writeFileSync(join(workspace, name), "x");
  const link = `https://ember.test/o/ws/st/cl%3AC1%3A${m.threadTs}`;
  await r.call(key, "chat_post", { to, text: "图在这", files: ["shot.png"] });
  assert.deepEqual([r.chat.lastText(), r.chat.files.at(-1)], ["图在这", ["shot.png"]]);
  await r.call(key, "chat_post", { to, text: "图表", files: ["shot.png", "weather.html"] });
  assert.equal(r.chat.lastText(), "图表");
  assert.deepEqual(r.chat.files.at(-1), ["shot.png", "weather.html"]);
  const last = r.said(r.thread("C1", m.threadTs).id).at(-1)!;
  assert.deepEqual([last.text, last.attachments.length], ["图表\n\n[weather.html](weather.html)", 2], "still.fail keeps both, the figure placed");
  r.chat.noFiles = true;
  await r.call(key, "chat_post", { to, text: "再看", files: ["shot.png"] });
  assert.equal(r.chat.lastText(), `再看\n\n<${link}?file=shot.png|在 still.fail 中查看附件>`, "no files:write: linked as before");
  assert.deepEqual(r.chat.files.at(-1), []);
  await r.close();
});

// ── titles ──

test("an agent can name a chat as soon as its topic is clear without posting a message", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  sayIn(r.hub, thread.id, "local", "登录失败了，帮我排查");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const before = r.said(thread.id).length;
  r.store.setRead("local", thread.id, r.store.lastEntry(thread.id));

  assert.equal(await r.call(key, "chat_post", { to, title: "  登录\n排查。 " }), 'Titled the chat "登录 排查".');
  assert.equal(r.store.getThread(thread.id)!.autoTitle, "登录 排查", "the first title appears even while the chat is open");
  assert.equal(r.said(thread.id).length, before, "titling alone does not add a message");
  assert.equal(await r.call(key, "chat_post", { to, title: "登录 排查" }), "The chat already has that title.");
  const [other] = newSession(r.hub, web("other"));
  assert.ok((await r.refused(other, "chat_post", { to, title: "别人的对话" })).includes("not a conversation of this session"));
  assert.ok((await r.refused(key, "chat_post", { to, title: " 。 " })).includes("title is empty"));
  assert.ok((await r.refused(key, "chat_post", { to, title: "登录", kind: "all_done", done: "完成" })).includes("only to and title"));
  r.store.setThreadTitle(thread.id, "自己起的名字");
  assert.ok((await r.call(key, "chat_post", { to, title: "登录问题" })).includes("people named this chat"));
  assert.equal(r.store.getThread(thread.id)!.title, "自己起的名字");
  assert.equal(r.said(thread.id).length, before);
  archive(r.hub, key, true);
  assert.ok((await r.refused(key, "chat_post", { to, title: "登录问题" })).includes("archived by hand"));
  await r.close();
});

test("naming a Slack conversation alone does not send a Slack message", async () => {
  const r = new Rig();
  const m = say("<@UBOT> 帮我查构建失败");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  const before = r.said(r.thread("C1", m.threadTs).id).length;
  assert.equal(await r.call(key, "chat_post", { to, title: "构建失败" }), 'Titled the chat "构建失败".');
  assert.equal(r.thread("C1", m.threadTs).autoTitle, "构建失败");
  assert.equal(r.said(r.thread("C1", m.threadTs).id).length, before);
  assert.equal(r.chat.posts.length, 0);
  await r.close();
});

test("an agent names its chat once, and again immediately when allowed even while open; never over people's name", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  sayIn(r.hub, thread.id, "local", "帮我看下这个");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const post = (title: string) => r.call(key, "chat_post", { to, text: "ok", title });
  const named = () => r.store.getThread(thread.id)!.autoTitle;
  // Its model asks again: it has read what people said meanwhile (else its post says it had not).
  const read = () => r.claude.last().events({ type: "live", event: { kind: "phase", phase: "requesting" } });
  assert.equal(await post("  登录\n排查。 "), `Posted to ${to}. Titled the chat "登录 排查".`);
  assert.equal(named(), "登录 排查");
  assert.equal(await post("登录 排查"), `Posted to ${to}.`, "the same name: nothing to say");
  assert.ok((await post("登录问题排查")).includes("Title not changed: people have said too little"));
  for (let n = 0; n < 5; n++) sayIn(r.hub, thread.id, "local", `再看 ${n}`);
  await settle();
  read();
  assert.ok((await post("部署失败")).endsWith('Titled the chat "部署失败".'));
  assert.equal(r.store.autoTitle(thread.id).changes, 1);
  // Someone has the chat open right now: renaming still takes effect immediately.
  for (let n = 0; n < 5; n++) sayIn(r.hub, thread.id, "local", `又一件 ${n}`);
  r.store.setRead("local", thread.id, r.store.lastEntry(thread.id));
  await settle();
  read();
  assert.ok((await post("证书过期")).endsWith('Titled the chat "证书过期".'));
  assert.equal(named(), "证书过期");
  assert.equal(r.store.autoTitle(thread.id).changes, 2);
  // A name people gave stays.
  r.store.setThreadTitle(thread.id, "值班");
  assert.ok((await post("别的")).includes("Title not changed: people named this chat"));
  // No title given: the post as before.
  assert.equal(await r.call(key, "chat_post", { to, text: "ok" }), `Posted to ${to}.`);
  await r.close();
});

test("a Slack agent names its list entry, with the same rename limits and a manual title kept", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  const post = (title: string) => r.call(key, "chat_post", { to, text: "ok", title });
  const thread = r.thread("C1", m.threadTs);
  assert.ok((await post("登录排查")).endsWith('Titled the chat "登录排查".'));
  assert.equal(r.thread("C1", m.threadTs).autoTitle, "登录排查");
  assert.equal(await post("登录排查"), `Posted to ${to}.`);
  assert.ok((await post("部署失败")).includes("people have said too little"));
  for (let change = 0; change < 3; change++) {
    for (let n = 0; n < 5; n++) await r.accept(reply(m, `${20000 + change * 5 + n}.000100`, "继续排查"));
    await settle();
    r.claude.last().reads();
    const said = await post(`新话题 ${change}`);
    assert.ok(said.includes(change < 2 ? "Titled the chat" : "changed as often as it may be"), said);
  }
  r.store.setThreadTitle(thread.id, "手动标题");
  assert.ok((await post("自动标题")).includes("people named this chat"));
  assert.equal(r.thread("C1", m.threadTs).title, "手动标题");
  await r.close();
});

test("a chat that starts a watch may be renamed for it at once", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  sayIn(r.hub, thread.id, "local", "帮我盯着 CI");
  await settle();
  const to = `CHAT/${thread.threadTs}`;
  const post = (title: string) => r.call(key, "chat_post", { to, text: "ok", title });
  assert.ok((await post("CI")).endsWith('Titled the chat "CI".'));
  assert.ok((await post("监控 · CI")).includes("Title not changed: people have said too little"));
  r.store.insertJob({ id: "job_w", sessionKey: key, name: "盯 CI", command: "sleep 600", cwd: "/", port: null, token: "tw", state: "running", pgid: null, exitCode: null, startedAt: Date.now(), endedAt: null, restarts: 0, log: "/dev/null", watch: true });
  assert.ok((await post("监控 · CI")).endsWith('Titled the chat "监控 · CI".'), "a watch runs: at once");
  await r.close();
});

test("a watch permits renaming without reading its session's job history", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, web("local"));
  try {
    r.store.setAutoTitle(thread.id, "CI", false);
    const job = (id: string, state: string, watch: boolean) => ({ id, sessionKey: key, name: id, command: "true", cwd: "/", port: null,
      token: id, state, pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch });
    for (let i = 0; i < 100; i++) r.store.insertJob(job(`ended-${i}`, "exited", true));
    r.store.insertJob(job("active-watch", "running", true));
    r.store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "jobs" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.equal(nameChat(r.hub, thread, "监控 · CI"), ' Titled the chat "监控 · CI".');
    } finally { r.store.db.setAuthorizer(null); }
  } finally { await r.close(); }
});

test("titles are one short line", () => {
  assert.equal(cleanTitle("  修一下\n登录。"), "修一下 登录");
  assert.equal(Array.from(cleanTitle("长".repeat(40))).length, 30);
  assert.equal(cleanTitle(" 。 "), "");
});

// ── slack_api ──

test("slack_api calls Slack as the session's bot; a thread it writes in becomes its own; one another session has is refused", async () => {
  const r = new Rig();
  const [mine, theirs] = [say("<@UBOT> look around"), say("<@UBOT> something else")];
  await r.accept(mine);
  await r.accept(theirs);
  await settle();
  const key = sessionKey("cl", "C1", mine.threadTs);
  const history = { ok: true, messages: [{ ts: "1.1", text: "hello" }] };
  r.chat.answers.set("conversations.history", history);
  assert.equal(await r.call(key, "slack_api", { method: "conversations.history", params: { channel: "C1", limit: 1 } }), JSON.stringify(history));
  assert.deepEqual(r.chat.calls.at(-1), ["conversations.history", { channel: "C1", limit: 1 }]);
  // Not the app itself, and not another session's thread.
  assert.ok((await r.refused(key, "slack_api", { method: "apps.manifest.update", params: {} })).includes("not for agents"));
  assert.ok((await r.refused(key, "slack_api", { method: "chat.postMessage", params: { channel: "C1", thread_ts: theirs.threadTs, text: "hi" } })).includes("another session's"));
  // A new message: its thread is this session's now, and a reply there comes to it.
  r.chat.answers.set("chat.postMessage", { ok: true, ts: "7777.1" });
  await r.call(key, "slack_api", { method: "chat.postMessage", params: { channel: "C2", text: "a new topic" } });
  const started = r.thread("C2", "7777.1");
  assert.deepEqual(
    r.store.threadSessions(started.id).map((m) => m.session),
    [key],
  );
  assert.deepEqual(
    r.said(started.id).map((m) => [m.authorKind, m.text]),
    [["agent", "a new topic"]],
  );
  const agent = r.claude.sessions.find((s) => s.options.route === key)!;
  await r.call(key, "chat_state", { kind: "final" });
  agent.complete();
  await settle();
  await r.accept(say("a reply to it", { channel: "C2", threadTs: "7777.1", ts: "7777.2", addressed: false }));
  await settle();
  assert.ok(agent.prompts.at(-1)!.includes("a reply to it"));
  await r.close();
});

test("slack_api with save_files saves the files in its answer into the session's uploads and starts with their paths", async () => {
  const r = new Rig();
  const mine = say("<@UBOT> look at that thread");
  await r.accept(mine);
  await settle();
  const key = sessionKey("cl", "C1", mine.threadTs);
  const shot = { id: "F1", name: "shot.png", size: 3, mode: "hosted", url_private_download: "https://files.slack.com/F1/shot.png" };
  const answer = { ok: true, messages: [{ ts: "1.1", text: "look", files: [shot, { id: "F2", name: "held.png", mode: "hidden_by_limit" }] }] };
  r.chat.answers.set("conversations.replies", answer);
  r.chat.shared.set("F1", "png");
  // Asked only with save_files.
  assert.equal(await r.call(key, "slack_api", { method: "conversations.replies", params: { channel: "C9", ts: "1.1" } }), JSON.stringify(answer));
  const said = JSON.parse(await r.call(key, "slack_api", { method: "conversations.replies", params: { channel: "C9", ts: "1.1" }, save_files: true }));
  assert.equal(said.saved_files.length, 1);
  assert.equal(said.saved_files[0].name, "shot.png");
  assert.equal(readFileSync(said.saved_files[0].path, "utf8"), "png");
  assert.ok(said.not_saved.includes("held.png"), said.not_saved);
  assert.equal(said.messages[0].text, "look");
});

test("a still.fail chat calls slack_api as the station's Slack bot, chosen by name when several fit", async () => {
  const r = new Rig();
  const [key] = newSession(r.hub, web());
  await settle();
  // Two Slack bots are bound to Claude here (cl and team): which one is the chat's to say.
  const refusal = await r.refused(key, "slack_api", { method: "chat.postMessage", params: { channel: "C5", text: "hi" } });
  assert.ok(refusal.includes("give bot= one of") && refusal.includes("cl (Claude bot)") && refusal.includes("team"), refusal);
  assert.ok((await r.refused(key, "slack_api", { method: "auth.test", bot: "nobody" })).includes('no Slack bot "nobody"'));
  // Named by its bot name: a new message in a channel, whose thread is this chat's now.
  r.chat.answers.set("chat.postMessage", { ok: true, ts: "8888.1" });
  await r.call(key, "slack_api", { method: "chat.postMessage", params: { channel: "C5", text: "for the team" }, bot: "Claude bot" });
  assert.deepEqual(r.chat.calls.at(-1), ["chat.postMessage", { channel: "C5", text: "for the team" }]);
  const started = r.thread("C5", "8888.1");
  assert.deepEqual(r.store.threadSessions(started.id).map((m) => [m.session, m.connect]), [[key, "cl"]]);
  // Named by its id: another bot.
  r.gptChat.answers.set("auth.test", { ok: true, user_id: "UGPT" });
  assert.equal(await r.call(key, "slack_api", { method: "auth.test", bot: "gpt" }), JSON.stringify({ ok: true, user_id: "UGPT" }));
  await r.close();
});

// ── session_send ──

test("an agent writes to another session's chat, which sees whom it is from", async () => {
  const r = new Rig({ link: true });
  const [a, b] = [say("<@UBOT> build it"), say("<@UBOT> test it")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  const linkB = `https://ember.test/o/ws/st/${keyB.replaceAll(":", "%3A")}`;
  const posted = r.chat.posts.length;
  const [threadA, threadB] = [r.thread("C1", a.threadTs).id, r.thread("C1", b.threadTs).id];
  const entries = (thread: number) => (r.store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread = ?").get(thread) as { n: number }).n;
  const [entriesA, entriesB] = [entries(threadA), entries(threadB)];
  const sent = await r.call(keyA, "session_send", { to: linkB, text: "the build is at /tmp/out" });
  assert.ok(sent.includes(`C1/${b.threadTs}`) && sent.includes(keyB), sent);
  // A letter: kept in B's chat's own log of letters, not among what is said there (its entries, numbered, paged and
  // synced as the chat), posted nowhere (not in Slack), headed with A's chat, and handed to B.
  assert.equal(r.chat.posts.length, posted, "posted nowhere");
  assert.deepEqual([entries(threadA), entries(threadB)], [entriesA, entriesB], "no entry of either chat");
  const linkA = `https://ember.test/o/ws/st/${keyA.replaceAll(":", "%3A")}`;
  const [last] = r.letters(threadB);
  const said = last!.text;
  assert.ok(matches(said, [`<${linkA}|`, ">", "\n\nthe build is at /tmp/out"]), said);
  assert.deepEqual([last!.n, last!.authorKind, last!.author, last!.letter?.way, last!.letter?.link], [1, "agent", keyA, "in", linkA]);
  assert.deepEqual(
    r.store.pendingMessages(keyB).map((p) => [p.message.text, p.message.apart]),
    [[said, true]],
  );
  // Read, it is not handed again.
  r.store.markDelivered(keyB, r.store.pendingMessages(keyB).map(handedOf));
  assert.deepEqual(r.store.pendingMessages(keyB), []);
  // Kept in A's chat's own log too, going out, by its agent: handed to no one.
  const [out] = r.letters(threadA);
  assert.deepEqual([out!.author, out!.letter?.way, out!.letter?.link, out!.text.endsWith("\n\nthe build is at /tmp/out")], [keyA, "out", linkB, true]);
  assert.deepEqual(r.store.pendingMessages(keyA), [], "not handed back to its sender");
  // Each chat counts its letters (its summary: how many, how far their log goes).
  const summary = r.store.listThreads("", null, threadB)[0]!;
  assert.deepEqual([summary.letters, summary.lettersLast], [1, 1]);
  // By session key too; not to itself, nor into a conversation it is in.
  await r.call(keyB, "session_send", { to: keyA, text: "tests pass" });
  assert.ok((await r.refused(keyA, "session_send", { to: keyA, text: "hi" })).includes("chat_post"));
  assert.ok((await r.refused(keyA, "session_send", { to: `C1/${a.threadTs}`, text: "hi" })).includes("chat_post"));
  await r.close();
});

test("a chat archived by hand takes no messages: session_send and chat_post are refused, and it is not brought back", async () => {
  const r = new Rig({ link: true });
  const [a, b] = [say("<@UBOT> build it"), say("<@UBOT> test it")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  archive(r.hub, keyB, true);
  await settle();
  assert.ok((await r.refused(keyA, "session_send", { to: keyB, text: "tests pass?" })).includes("archived by hand"));
  assert.ok((await r.refused(keyB, "chat_post", { to: `C1/${b.threadTs}`, text: "late words" })).includes("archived by hand"));
  assert.ok(r.store.getSession(keyB)!.archivedAt !== null);
  assert.deepEqual(r.store.pendingMessages(keyB), []);
  // Shown again, it takes them.
  archive(r.hub, keyB, false);
  const sent = await r.call(keyA, "session_send", { to: keyB, text: "tests pass?" });
  assert.ok(sent.includes(keyB), sent);
  await r.close();
});

test("a message to another station's session goes through the station transport, and arrives there", async () => {
  const r = new Rig({ link: true });
  const [a, b] = [say("<@UBOT> build it"), say("<@UBOT> test it")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  const asked: [string, Json][] = [];
  r.hub.onPeer(async (station, request) => {
    asked.push([station, request]);
    return { thread: "CHAT/2.000001" };
  });
  const sent = await r.call(keyA, "session_send", { to: "https://ember.test/o/ws/far/s%3A1", text: "ready?" });
  assert.ok(sent.includes("station far") && sent.includes("CHAT/2.000001"), sent);
  const [station, request] = asked.pop()!;
  assert.equal(station, "far");
  assert.deepEqual([request.method, request.to, request.session, request.text], ["session.message", "s:1", keyA, "ready?"]);
  assert.equal(request.from.link, `https://ember.test/o/ws/st/${keyA.replaceAll(":", "%3A")}`);
  // The other way: what a session there sent arrives in B's chat, from that station's session.
  const from = { title: "部署", link: "https://ember.test/o/ws/far/s%3A1" };
  const got = await fromPeer(r.hub, "far", { method: "session.message", session: "s:1", to: keyB, text: "yes", from });
  assert.equal(got.thread, `C1/${b.threadTs}`);
  // (a letter: kept in the chat's own log of them)
  const last = r.letters(r.thread("C1", b.threadTs).id).at(-1)!;
  assert.deepEqual([last.authorKind, last.author], ["agent", "far/s:1"]);
  assert.ok(matches(last.text, ["<https://ember.test/o/ws/far/s%3A1|部署>", "\n\nyes"]), last.text);
  assert.equal(r.store.pendingMessages(keyB).length, 1);
  await assert.rejects(fromPeer(r.hub, "far", { session: "s:1", to: "nobody", text: "yes" }));
  await r.close();
});

test("a chat on another station of the workspace is read there, by its link", async () => {
  const r = new Rig({ link: true });
  const [a, b] = [say("<@UBOT> build it"), say("<@UBOT> what did it find?")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  await r.call(keyA, "chat_post", { to: `C1/${a.threadTs}`, text: "the build is green" });
  const asked: [string, Json][] = [];
  r.hub.onPeer(async (station, request) => {
    asked.push([station, request]);
    return { text: "Conversation CHAT/2.000001; its agents: s:1.\nit works" };
  });
  // A still.fail link and a chat's page (as a reference is written) both name the station.
  for (const chat of ["https://ember.test/o/ws/far/s%3A1", "/w/ws/s/far/chats/s%3A1?history=s%3A1&entry=3"]) {
    const read = await r.call(keyB, "chat_read", { chat, limit: 5 });
    assert.ok(matches(read, ["station far", "it works"]), read);
    const [station, request] = asked.pop()!;
    assert.equal(station, "far");
    assert.deepEqual([request.method, request.tool, request.session, request.args], ["session.read", "chat_read", keyB, { chat, limit: 5 }]);
  }
  await r.call(keyB, "session_history", { chat: "https://ember.test/o/ws/far/s%3A1" });
  assert.equal(asked.pop()![1].tool, "session_history");
  // This station's own link is read here.
  const here = await r.call(keyB, "chat_read", { chat: `https://ember.test/o/ws/st/${keyA.replaceAll(":", "%3A")}` });
  assert.ok(here.includes("the build is green") && !here.includes("station far"), here);
  assert.equal(asked.length, 0);
  // A station from before reads: it says so.
  r.hub.onPeer(async () => {
    throw new Refused("remote tasks are not enabled for this source station");
  });
  assert.ok((await r.refused(keyB, "chat_read", { chat: "https://ember.test/o/ws/far/s%3A1" })).includes("not updated yet"));
  // The other way: what a session there reads here.
  const got = await forPeer(r.hub, "far", { method: "session.read", session: "s:1", tool: "chat_read", args: { chat: keyA } });
  assert.ok(matches(got.text, [`Conversation C1/${a.threadTs}`, "the build is green"]), got.text);
  const steps = await forPeer(r.hub, "far", { method: "session.read", session: "s:1", tool: "session_history", args: { chat: keyA } });
  assert.equal(steps.text, `Session ${keyA} has no execution history yet.`);
  await assert.rejects(forPeer(r.hub, "far", { method: "session.read", session: "s:1", tool: "chat_post", args: { chat: keyA } }));
  await assert.rejects(forPeer(r.hub, "far", { method: "session.read", session: "s:1", tool: "chat_read", args: {} }));
  await r.close();
});

test("files go between stations: a chat's attachments come with reading it, and a message takes its files along", async () => {
  const r = new Rig({ link: true });
  const [a, b] = [say("<@UBOT> draw it"), say("<@UBOT> what did it draw?")];
  await r.accept(a);
  await r.accept(b);
  await settle();
  const [keyA, keyB] = [sessionKey("cl", "C1", a.threadTs), sessionKey("cl", "C1", b.threadTs)];
  // Station "far" is this one again, answering as it would over the transport.
  const asked: string[] = [];
  r.hub.onPeer(async (_station, request) => {
    asked.push(request.method);
    if (request.method === "session.read") return forPeer(r.hub, "near", request);
    if (request.method === "session.file") return fileForPeer(r.hub, request);
    if (request.method === "session.put") return putForPeer(r.hub, "near", request);
    return fromPeer(r.hub, "near", request);
  });
  const workspaceA = r.session(keyA).workspace;
  writeFileSync(join(workspaceA, "pose.png"), "pixels");
  const big = Buffer.alloc(FETCHED + 1, 7);
  writeFileSync(join(workspaceA, "take.mp4"), big);
  await r.call(keyA, "chat_post", { to: `C1/${a.threadTs}`, text: "drawn", files: ["pose.png", "take.mp4"] });
  const [pose, take] = r.said(r.thread("C1", a.threadTs).id).at(-1)!.attachments;
  const chat = `https://ember.test/o/ws/far/${keyA.replaceAll(":", "%3A")}`;
  const read = await r.call(keyB, "chat_read", { chat });
  const here = join(r.session(keyB).workspace, "uploads", "far");
  assert.ok(read.includes(`- ${join(here, basename(pose!.path))} (pose.png`), read);
  assert.equal(readFileSync(join(here, basename(pose!.path)), "utf8"), "pixels");
  assert.ok(read.includes(`- ${take!.path} (take.mp4`) && read.includes("fetch one with chat_read fetch=") && read.includes(`${take!.path} (${big.length} bytes)`), "a large one is left there");
  const fetched = await r.call(keyB, "chat_read", { chat, fetch: [take!.path] });
  assert.ok(fetched.includes(`- ${join(here, basename(take!.path))} (take.mp4`) && !fetched.includes("fetch one"), fetched);
  assert.ok(readFileSync(join(here, basename(take!.path))).equals(big));
  // Only a chat's own files: not another path, not out of its uploads.
  await assert.rejects(fileForPeer(r.hub, { chat, path: join(workspaceA, "pose.png") }), /not a file of that chat/);
  await assert.rejects(fileForPeer(r.hub, { chat, path: join(workspaceA, "uploads", "..", "pose.png") }), /not a file of that chat/);
  await assert.rejects(fileForPeer(r.hub, { chat: keyB, path: pose!.path }), /not a file of that chat/);
  // A station from before files: the read still comes, its files are said to be left.
  r.hub.onPeer(async (_station, request) => {
    if (request.method === "session.read") return forPeer(r.hub, "near", request);
    throw new Refused("session and task key are required (at most 256 / 128 bytes)");
  });
  rmSync(here, { recursive: true });
  const old = await r.call(keyB, "chat_read", { chat });
  assert.ok(old.includes("not updated yet to give files") && old.includes("drawn"), old);
  // A message takes its files along: sent ahead, then kept with it in the chat there.
  r.hub.onPeer(async (_station, request) => {
    asked.push(request.method);
    if (request.method === "session.put") return putForPeer(r.hub, "near", request);
    return fromPeer(r.hub, "near", request);
  });
  asked.length = 0;
  writeFileSync(join(r.session(keyB).workspace, "answer.txt"), "seen it");
  await r.call(keyB, "session_send", { to: chat, text: "here is mine", files: ["answer.txt"] });
  assert.deepEqual(asked, ["session.put", "session.message"]);
  const got = r.letters(r.thread("C1", a.threadTs).id).at(-1)!;
  assert.deepEqual([got.author, got.attachments.map((f) => f.name)], [`near/${keyB}`, ["answer.txt"]]);
  assert.ok(got.attachments[0]!.path.startsWith(join(workspaceA, "uploads")));
  assert.equal(readFileSync(got.attachments[0]!.path, "utf8"), "seen it");
  // A file that did not all arrive is not posted.
  await assert.rejects(fromPeer(r.hub, "near", { session: keyB, to: keyA, text: "again", files: [{ id: "nope", name: "x.txt" }] }), /did not all arrive/);
  // On this station too: copied into the uploads of the chat it goes to.
  await r.call(keyB, "session_send", { to: keyA, text: "and again", files: ["answer.txt"] });
  const local = r.letters(r.thread("C1", a.threadTs).id).at(-1)!;
  assert.ok(local.attachments[0]!.path.startsWith(join(workspaceA, "uploads")) && local.text.endsWith("and again"));
  assert.ok((await r.refused(keyB, "session_send", { to: chat, text: "x", files: ["missing.txt"] })).includes("no such file"));
  // Packed with its archived workspace: read out once, every chunk after from what was read out.
  const room = roomOf(r.config.dataDir, workspaceA)!;
  await packWorkspaceIf(room, () => true);
  assert.ok(!existsSync(take!.path));
  const chunks: Buffer[] = [];
  for (let offset = 0, eof = false; !eof; ) {
    const got = await fileForPeer(r.hub, { chat, path: take!.path, offset });
    chunks.push(Buffer.from(got.data, "base64"));
    offset += chunks.at(-1)!.length;
    eof = got.eof;
  }
  assert.ok(Buffer.concat(chunks).equals(big));
  await r.close();
});

// ── chat_create ──

/// Whoever reads the list in these tests: the station's own viewer, of every workspace.
const LIST_VIEWER = { sub: "local", email: "local", name: "local", role: "owner", workspace: "ws", device: "d" } as any;

/// The fake runtime session of session `key`.
const runtimeOf = (r: Rig, key: string) => {
  const found = [...r.claude.sessions, ...r.codex.sessions].filter((s) => s.options.key === key).at(-1);
  if (!found) throw new Error(`no runtime session of ${key}`);
  return found;
};

test("an agent opens a chat here: it begins with its message, goes to its starter, and tells it how each turn ends", async () => {
  const r = new Rig({ link: true });
  const a = say("<@UBOT> ship it");
  await r.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  const linkA = `https://ember.test/o/ws/st/${keyA.replaceAll(":", "%3A")}`;
  writeFileSync(join(r.session(keyA).workspace, "notes.txt"), "the plan");
  const sessions = r.store.listSessions().length;
  const said = await r.call(keyA, "chat_create", { key: "android", text: "build the android app", title: "安卓构建", files: ["notes.txt"] });
  assert.equal(r.store.listSessions().length, sessions + 1);
  const opened = r.store.openedBy(keyA);
  assert.equal(opened.length, 1);
  const child = opened[0]!.child;
  assert.ok(said.includes(`https://ember.test/o/ws/st/${child.replaceAll(":", "%3A")}`) && said.includes("this station"), said);
  // A chat of its own, started by whoever started the opener's, with the opener's runtime.
  const row = r.session(child);
  assert.equal(row.runtime, "claude");
  const thread = r.store.homeChat(child)!;
  assert.equal(thread.title, "安卓构建");
  assert.equal(thread.createdBy, r.thread("C1", a.threadTs).createdBy);
  // Its first message: the opener's, headed as its opening, with the file; handed to its agent.
  const [first] = r.said(thread.id);
  const [before, after] = tr(stationLang(), "station.session.openedBy", { from: "\u0000" }).split("\u0000");
  assert.deepEqual([first!.authorKind, first!.author], ["agent", keyA]);
  assert.ok(first!.text.startsWith(`${before}[`) && first!.text.endsWith(`](${linkA})${after}\n\nbuild the android app`), first!.text);
  assert.deepEqual(first!.attachments.map((f) => f.name), ["notes.txt"]);
  assert.ok(first!.attachments[0]!.path.startsWith(join(row.workspace, "uploads")));
  await settle();
  assert.ok(runtimeOf(r, child).prompts[0]!.includes("build the android app"));
  // Said in the opener's chat, for people.
  const notice = r.said(r.thread("C1", a.threadTs).id).at(-1)!;
  assert.equal(notice.authorKind, "ember");
  assert.ok(notice.text.includes(`<https://ember.test/o/ws/st/${child.replaceAll(":", "%3A")}|安卓构建>`), notice.text);
  // Its row in the list leads back to the chat that opened it, named as that chat was then; the opener's row says
  // nothing of it, and archiving the opener leaves it as it was.
  const listed = () => new Map(chats(makeStore(r.store.db, r.dir), LIST_VIEWER, false).map((x: any) => [x.id, x]));
  assert.deepEqual(listed().get(child).opener, { session: keyA, title: sender(r.hub, keyA)[0] });
  assert.equal(listed().get(keyA).opener, undefined);
  // the opener's row lists the chats it opened
  assert.deepEqual(listed().get(keyA).opened, [{ session: child, title: "安卓构建" }]);
  r.store.setArchived(keyA, true, "manual");
  assert.deepEqual(listed().get(child).opener?.session, keyA);
  r.store.setArchived(keyA, false, "manual");
  // The same key again: that chat, nothing new.
  const again = await r.call(keyA, "chat_create", { key: "android", text: "build the android app" });
  assert.ok(again.includes("already opened"), again);
  assert.equal(r.store.listSessions().length, sessions + 1);
  assert.equal(r.said(thread.id).length, 1);
  // It opens none itself.
  assert.ok((await r.refused(child, "chat_create", { key: "more", text: "and more" })).includes("opens none"));
  // Its turn ends all_done: the opener is told, with its done.
  await r.call(child, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "built", kind: "all_done", done: "安卓包已经构建好，apk 在 uploads 里" });
  runtimeOf(r, child).complete();
  await settle();
  const told = [...runtimeOf(r, keyA).steers, ...runtimeOf(r, keyA).prompts.slice(1)].join("\n");
  assert.ok(matches(told, ["安卓构建", "all_done", "安卓包已经构建好"]), told);
  assert.equal(r.store.openedBy(keyA)[0]!.state, "all_done");
  await r.close();
});

test("an agent can open more than eight unfinished chats without duplicating a key", async () => {
  const r = new Rig({ link: true });
  const a = say("<@UBOT> split it up");
  await r.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  for (let i = 0; i < 12; i++) await r.call(keyA, "chat_create", { key: `part-${i}`, text: `part ${i}` });
  const opened = r.store.openedBy(keyA);
  assert.equal(opened.length, 12);
  assert.equal(new Set(opened.map((o) => o.child)).size, 12);
  assert.ok(opened.every((o) => o.state !== "all_done"));
  const again = await r.call(keyA, "chat_create", { key: "part-0", text: "part 0" });
  assert.ok(again.includes("already opened"), again);
  assert.equal(r.store.openedBy(keyA).length, 12);
  assert.ok((await r.refused(keyA, "chat_create", { text: "no key" })).includes("key is required"));
  await r.close();
});

test("opening a chat again checks its author through the reader", async () => {
  const r = new Rig({ link: true });
  const original = r.store.messagesBefore.bind(r.store);
  try {
    const a = say("<@UBOT> open it");
    await r.accept(a);
    await settle();
    const parent = sessionKey("cl", "C1", a.threadTs);
    await r.call(parent, "chat_create", { key: "once", text: "first" });
    const child = r.store.openedBy(parent)[0]!.child;
    const thread = r.store.homeChat(child)!;
    const reads: unknown[] = [];
    r.hub.openedChatSaid = async (...args) => { reads.push(args); return true; };
    r.store.messagesBefore = () => { throw new Error("station message lookup used"); };
    assert.match(await r.call(parent, "chat_create", { key: "once", text: "first" }), /already opened/);
    assert.deepEqual(reads, [[thread.id, parent, true]]);
    r.store.messagesBefore = original;
    assert.equal(r.said(thread.id).length, 1);
  } finally { r.store.messagesBefore = original; await r.close(); }
});

test("concurrent opens with the same key send the first message once while the reader waits", async () => {
  const r = new Rig({ link: true });
  const entered = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  try {
    const a = say("<@UBOT> open it");
    await r.accept(a);
    await settle();
    const parent = sessionKey("cl", "C1", a.threadTs);
    let reads = 0;
    r.hub.openedChatSaid = async (thread, author, agentOnly) => {
      const found = r.store.messagesBefore(thread, null, 200).some((m) => m.author === author && (!agentOnly || m.authorKind === "agent"));
      if (++reads === 1) { entered.resolve(); await release.promise; }
      return found;
    };
    const first = r.call(parent, "chat_create", { key: "once", text: "first" });
    void first.catch(() => {});
    await entered.promise;
    const second = r.call(parent, "chat_create", { key: "once", text: "first" });
    void second.catch(() => {});
    await new Promise<void>((resolve) => setImmediate(resolve));
    release.resolve();
    await Promise.all([first, second]);
    const opened = r.store.openedBy(parent);
    assert.equal(opened.length, 1);
    assert.equal(r.said(r.store.homeChat(opened[0]!.child)!.id).length, 1);
  } finally { release.resolve(); await r.close(); }
});

test("a failed first-message check leaves the same chat key available for retry", async () => {
  const r = new Rig({ link: true });
  try {
    const a = say("<@UBOT> open it");
    await r.accept(a);
    await settle();
    const parent = sessionKey("cl", "C1", a.threadTs);
    let reads = 0;
    r.hub.openedChatSaid = async () => {
      if (++reads === 1) throw new Error("reader stopped");
      return false;
    };
    await assert.rejects(r.call(parent, "chat_create", { key: "once", text: "first" }), /reader stopped/);
    assert.match(await r.call(parent, "chat_create", { key: "once", text: "first" }), /already opened/);
    const opened = r.store.openedBy(parent);
    assert.equal(opened.length, 1);
    assert.equal(r.said(r.store.homeChat(opened[0]!.child)!.id).length, 1);
  } finally { await r.close(); }
});

test("a peer retry checks its author through the reader", async () => {
  const r = new Rig({ link: true });
  const original = r.store.messagesBefore.bind(r.store);
  try {
    const request = { session: "parent", key: "once", runtime: "claude" };
    const made = await createForPeer(r.hub, "near", request);
    const thread = r.store.homeChat(made.session)!;
    const reads: unknown[] = [];
    r.hub.openedChatSaid = async (...args) => { reads.push(args); return true; };
    r.store.messagesBefore = () => { throw new Error("station message lookup used"); };
    const again = await createForPeer(r.hub, "near", request);
    assert.equal(again.session, made.session);
    assert.equal(again.said, true);
    assert.deepEqual(reads, [[thread.id, "near/parent", false]]);
  } finally { r.store.messagesBefore = original; await r.close(); }
});

test("an agent opens a chat on another station: made there once per key, its first message and files sent once, its turns told back", async () => {
  // "near" opens a chat on "far" (named orchard); each answers the other as the transport would.
  const near = new Rig({ link: true });
  const far = new Rig({ link: true });
  const a = say("<@UBOT> test on the mac");
  await near.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  const asked: string[] = [];
  let farDown = false;
  near.hub.onPeer(async (station, request) => {
    if (request.method === "peers") return { workspace: "ws", stations: [{ id: "st", name: "cedar" }, { id: "far", name: "orchard" }], current: true };
    assert.equal(station, "far");
    asked.push(request.method);
    if (farDown) throw new Error("peer unavailable");
    if (request.method === CREATE) return createForPeer(far.hub, "near", request);
    if (request.method === "session.put") return putForPeer(far.hub, "near", request);
    return fromPeer(far.hub, "near", request);
  });
  far.hub.onPeer(async (station, request) => {
    assert.equal(station, "near");
    assert.equal(request.method, NOTICE);
    return noticeForPeer(near.hub, "far", request);
  });
  writeFileSync(join(near.session(keyA).workspace, "plan.txt"), "run them all");
  // Nothing used there yet, and two runtimes to choose from: not opened, the agent is told which to ask about.
  const which = await near.refused(keyA, "chat_create", { key: "tests", station: "orchard", text: "run the tests" });
  assert.ok(which.includes("no one model is clearly the most used") && which.includes("claude's default") && which.includes("codex's default"), which);
  assert.equal(far.store.listSessions().length, 0);
  asked.length = 0;
  const said = await near.call(keyA, "chat_create", { key: "tests", station: "orchard", runtime: "claude", text: "run the tests", title: "跑测试", files: ["plan.txt"] });
  assert.deepEqual(asked, [CREATE, "session.put", "session.message"]);
  assert.ok(said.includes("station far"), said);
  const [child] = far.store.listSessions().map((s) => s.key);
  assert.ok(child !== undefined && far.store.openerOf(child)!.parent === keyA);
  // Its row there leads back to the opener on this station, named as it was called.
  const row = chats(makeStore(far.store.db, far.dir), LIST_VIEWER, false).find((x: any) => x.id === child);
  assert.deepEqual(row.opener, { station: "near", session: keyA, title: sender(near.hub, keyA)[0] });
  // and the opener's here, the chat there it opened
  const opener = chats(makeStore(near.store.db, near.dir), LIST_VIEWER, false).find((x: any) => x.id === keyA);
  assert.deepEqual(opener.opened, [{ station: "far", session: child, title: "跑测试" }]);
  assert.deepEqual(near.store.openedBy(keyA).map((o) => [o.childStation, o.child]), [["far", child]]);
  const thread = far.store.homeChat(child!)!;
  assert.equal(thread.title, "跑测试");
  assert.equal(thread.createdBy, near.thread("C1", a.threadTs).createdBy);
  const [first] = far.said(thread.id);
  assert.equal(first!.author, `near/${keyA}`);
  const opening = tr(stationLang(), "station.session.openedBy", { from: "\u0000" }).split("\u0000")[0]!;
  assert.ok(first!.text.startsWith(`${opening}[`) && first!.text.includes(`](https://ember.test/o/ws/st/${keyA.replaceAll(":", "%3A")})`) && first!.text.endsWith("run the tests"), first!.text);
  assert.deepEqual(first!.attachments.map((f) => f.name), ["plan.txt"]);
  // Again with the key: the same chat, and its first message is not sent twice.
  asked.length = 0;
  near.store.db.prepare("DELETE FROM opened_chats").run();
  await near.call(keyA, "chat_create", { key: "tests", station: "far", text: "run the tests" });
  assert.deepEqual(asked, [CREATE]);
  assert.equal(far.store.listSessions().length, 1);
  assert.equal(far.said(thread.id).length, 1);
  // Its turn ends needing a person: the opener there is told.
  await far.call(child!, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "which device?", kind: "need_human", need: "选一台测试机" });
  await settle();
  runtimeOf(far, child!).complete();
  await settle();
  const told = [...runtimeOf(near, keyA).steers, ...runtimeOf(near, keyA).prompts.slice(1)].join("\n");
  assert.ok(matches(told, ["跑测试", "needs a person", "选一台测试机"]), told);
  assert.equal(near.store.openedBy(keyA)[0]!.state, "need_human");
  // Only the station a chat was opened on tells of it.
  assert.throws(() => noticeForPeer(near.hub, "elsewhere", { session: child, to: keyA, state: "all_done" }), /opened no chat/);
  // When the opener cannot be told, its chat says so; nothing is sent again.
  far.hub.onPeer(async () => {
    throw new Error("peer unavailable");
  });
  sayIn(far.hub, thread.id, "lee@example.com", "the pixel one");
  await settle();
  await far.call(child!, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "done", kind: "all_done", done: "测试全部通过，结果贴在上面" });
  runtimeOf(far, child!).complete();
  await settle();
  const last = far.said(thread.id).at(-1)!;
  assert.ok(last.authorKind === "ember" && last.text.includes("peer unavailable"), last.text);
  // A station that cannot be reached: not opened, and it says how to go on.
  farDown = true;
  const down = await near.refused(keyA, "chat_create", { key: "again", station: "far", text: "x" });
  assert.ok(down.includes("same key"), down);
  // One from before chats can be opened there says so.
  near.hub.onPeer(async (_station, request) => {
    if (request.method === "peers") return { stations: [{ id: "far", name: "orchard" }] };
    throw new Refused("remote tasks are not enabled for this source station");
  });
  assert.ok((await near.refused(keyA, "chat_create", { key: "old", station: "far", text: "x" })).includes("not updated yet"));
  assert.ok((await near.refused(keyA, "chat_create", { key: "nowhere", station: "mars", text: "x" })).includes("orchard"));
  await near.close();
  await far.close();
});

test("an agent opens a chat with a preset as a person would in the app: taken as it is, nothing given beside what it names", async () => {
  const near = new Rig({ link: true });
  near.edit((raw) => {
    raw.profiles[0].models = ["opus", "sonnet"];
  });
  const far = new Rig({ link: true, place: { workspace: "ws", station: "far" } });
  const a = say("<@UBOT> review it");
  await near.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  const asked: string[] = [];
  near.hub.onPeer(async (_station, request) => {
    if (request.method === "peers") return { workspace: "ws", stations: [{ id: "st", name: "cedar" }, { id: "far", name: "orchard" }], current: true };
    asked.push(request.method);
    if (request.method === CREATE || request.method === CREATE_PRESET) return createForPeer(far.hub, "st", request);
    return fromPeer(far.hub, "st", request);
  });
  const review = near.hub.presets.add(null, { name: "Review", dirs: [], instructions: "Read every line.", model: { model: "opus", runtime: "claude" } }, "local");
  near.hub.presets.add(null, { name: "Loose", dirs: [], instructions: "" }, "local");
  near.hub.presets.add(null, { name: "Far", dirs: [], instructions: "On orchard.", station: "ws/far" }, "local");

  // One that names its model runs it as it says; nothing of it can be given beside it.
  const said = await near.call(keyA, "chat_create", { key: "review", text: "review the PR", preset: "review" });
  const child = near.store.openedBy(keyA)[0]!.child;
  assert.ok(said.includes("this station"), said);
  assert.deepEqual([near.session(child).runtime, near.session(child).model], ["claude", "opus"]);
  assert.equal(presetCopyOf(near.session(child).workspace)?.id, review.id);
  for (const beside of [{ model: "sonnet" }, { runtime: "claude" }, { effort: "high" }, { fast: true }, { context: 200_000 }]) {
    const why = await near.refused(keyA, "chat_create", { key: "beside", text: "x", preset: review.id, ...beside });
    assert.ok(why.includes("leave runtime, model, effort, fast and context out"), why);
  }
  // One that names no model is chosen as without one, and kept with the chat.
  await near.call(keyA, "chat_create", { key: "loose", text: "x", preset: "Loose", model: "sonnet" });
  const loose = near.store.openedBy(keyA).find((o) => o.key === "loose")!.child;
  assert.deepEqual([near.session(loose).model, presetCopyOf(near.session(loose).workspace)?.name], ["sonnet", "Loose"]);
  // None named: no preset, whatever the opener's chat has.
  await near.call(keyA, "chat_create", { key: "none", text: "x", model: "sonnet" });
  const none = near.store.openedBy(keyA).find((o) => o.key === "none")!.child;
  assert.equal(presetCopyOf(near.session(none).workspace), null);
  // An unknown one: told those there are.
  const unknown = await near.refused(keyA, "chat_create", { key: "u", text: "x", preset: "Nope" });
  assert.ok(unknown.includes("Review, Loose, Far"), unknown);

  // One that names a station opens there with station left out, its copy taken by that station; on another, refused.
  asked.length = 0;
  await near.call(keyA, "chat_create", { key: "far", text: "x", preset: "Far", runtime: "claude" });
  assert.equal(asked[0], CREATE_PRESET);
  const there = far.store.listSessions().map((s) => s.key);
  assert.equal(there.length, 1);
  const copy = presetCopyOf(far.session(there[0]!).workspace);
  assert.deepEqual([copy?.name, copy?.instructions], ["Far", "On orchard."]);
  const elsewhere = await near.refused(keyA, "chat_create", { key: "far2", text: "x", preset: "Far", station: "cedar" });
  assert.ok(elsewhere.includes("only on station far"), elsewhere);
  // A station from before presets reached chat_create: refused, nothing opened there without the preset.
  near.hub.onPeer(async (_station, request) => {
    if (request.method === "peers") return { stations: [{ id: "far", name: "orchard" }] };
    throw new Refused("remote tasks are not enabled for this source station");
  });
  const old = await near.refused(keyA, "chat_create", { key: "old", text: "x", preset: "Far" });
  assert.ok(old.includes("not updated yet") && old.includes("with a preset"), old);
  await near.close();
  await far.close();
});

test("a chat opened on another station without a model runs what its starter uses most there, not its opener's", async () => {
  // As on 2026-10-19: the opener runs Claude's Opus here; orchard runs gpt-6-astra on codex and DeepSeek, no Opus.
  const near = new Rig({ link: true });
  const far = new Rig({ link: true });
  far.raw.profiles = [
    { id: "cx", runtime: "codex", home: "homes/cx", models: ["gpt-6-astra"] },
    { id: "ds", runtime: "claude", home: "homes/ds", models: ["deepseek-v4.1-flash"] },
  ];
  far.config = hubConfig(far.raw, far.dir);
  const a = say("<@UBOT> sign the app in on the mac");
  await near.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  assert.equal(near.session(keyA).model, "opus");
  near.hub.onPeer(async (_station, request) => {
    if (request.method === "peers") return { workspace: "ws", stations: [{ id: "st", name: "cedar" }, { id: "far", name: "orchard" }], current: true };
    if (request.method === CREATE) return createForPeer(far.hub, "near", request);
    return fromPeer(far.hub, "near", request);
  });
  far.hub.onPeer(async (_station, request) => noticeForPeer(near.hub, "far", request));
  const starter = near.thread("C1", a.threadTs).createdBy!;
  const used = (key: string, runtime: string, model: string, at: number) =>
    far.store.insertSession({ key, connect: "ds", runtime, profile: "cx", model, createdBy: starter, workspace: `/w/${key}`, token: `t-${key}`, createdAt: at, lastActiveAt: at });
  const now = far.hub.now();
  used("u1", "codex", "gpt-6-astra", now - 86_400_000);
  used("u2", "codex", "gpt-6-astra", now - 2 * 86_400_000);
  used("u3", "claude", "deepseek-v4.1-flash", now - 86_400_000);
  // Long ago, and someone else's: not counted.
  used("u4", "claude", "deepseek-v4.1-flash", now - 90 * 86_400_000);
  used("u5", "claude", "deepseek-v4.1-flash", now - 90 * 86_400_000);
  used("u6", "claude", "deepseek-v4.1-flash", now - 90 * 86_400_000);
  far.store.db.prepare("UPDATE sessions SET created_by = 'someone else', created_at = ? WHERE key IN ('u4', 'u5')").run(now);
  await near.call(keyA, "chat_create", { key: "login", station: "orchard", text: "run the login" });
  const child = far.store.openedWith("near", keyA, "login", "")!.child;
  assert.deepEqual([far.session(child).runtime, far.session(child).model], ["codex", "gpt-6-astra"]);
  // Close to it (3 to 2, the chat just opened counting too): asked.
  used("u7", "claude", "deepseek-v4.1-flash", now - 3600_000);
  const which = await near.refused(keyA, "chat_create", { key: "login-2", station: "orchard", text: "run the login" });
  assert.ok(which.includes("gpt-6-astra (runtime codex, 3 chats") && which.includes("deepseek-v4.1-flash (runtime claude, 2 chats"), which);
  // A runtime named: its model there.
  await near.call(keyA, "chat_create", { key: "login-3", station: "orchard", runtime: "claude", text: "run the login" });
  const third = far.store.openedWith("near", keyA, "login-3", "")!.child;
  assert.deepEqual([far.session(third).runtime, far.session(third).model], ["claude", "deepseek-v4.1-flash"]);
  await near.close();
  await far.close();
});

// ── the archive suggestion after all_done ──

/// A local decision provider (Jev's shape): tests routing and what is recorded, not a model's judgement.
async function provider(complete: boolean) {
  const server = createServer((req, res) => {
    req.resume();
    req.on("end", () => {
      // The default policy's options: answered (archive) or awaiting_review (not), the rest hardly.
      const [done, human] = complete ? [0.96, 0.01] : [0.01, 0.96];
      const probabilities = { ...Object.fromEntries(DEFAULT_POLICY.options.map((o) => [o.id, 0.005])), answered: done, awaiting_review: human };
      const body = JSON.stringify({ model: "test-jev", answers: { decision: { type: "choice", probabilities } } });
      res.writeHead(200, { "content-type": "application/json" }).end(body);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}/v1/systemone`, server };
}

function installDecisionProfile(r: Rig, endpoint: string) {
  r.edit((raw) => {
    raw.automaticDecisions = { completion: { enabled: true, model: "test-jev" } };
    raw.profiles[0].env = { TYPESAFE_API_KEY: "profile-test-key", TYPESAFE_BASE_URL: endpoint.replace(/\/systemone$/, "") };
  });
  const profile = r.config.profiles[0]!;
  const capability = { state: "ready", detail: "test", model: "test-jev", provider: "jev", fingerprint: fingerprint(profile), models: ["test-jev"] };
  r.hub.accounts.setHealth((id) => (id === profile.id ? { check: { decision: capability, state: "ok", detail: "", models: null, checkedAt: 0 } } : {}));
}

test("a chat the decision finds finished is recommended for the archive, until anyone speaks", async () => {
  const r = new Rig();
  const m = say("<@UBOT> what does this setting do?");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  const { url, server } = await provider(true);
  installDecisionProfile(r, url);
  const before = r.chat.texts().length;
  // The agent's word is taken at once: it posts, its turn ends all_done, and nothing waited for the model.
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "It controls retention.", kind: "all_done", done: "Explained the setting and its effect" });
  assert.equal(r.chat.texts().length, before + 1);
  await review(r.hub, key);
  assert.ok(r.store.archiveSuggested(r.thread("C1", m.threadTs).id), "the decision found nothing left to do");
  // Anyone saying anything since makes the recommendation stale: it goes by itself.
  await r.accept(reply(m, "9999.0001", "and the default?"));
  await settle();
  assert.ok(!r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
  server.close();
  await r.close();
});

test("an all_done is never held back, and a chat with something left is not recommended", async () => {
  const r = new Rig();
  const m = say("<@UBOT> ship the requested fix");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  const to = `C1/${m.threadTs}`;
  // The model says a person is needed: all_done and final both post and record all the same.
  const { url, server } = await provider(false);
  installDecisionProfile(r, url);
  for (const [tool, kind] of [["chat_post", "all_done"], ["chat_post", "final"], ["chat_state", "all_done"]] as const) {
    const before = r.chat.texts().length;
    await r.call(key, tool, { to, text: "Ready, approve merging?", kind, done: "Branch is ready and tests passed" });
    assert.equal(r.chat.texts().length, before + (tool === "chat_post" ? 1 : 0));
  }
  await review(r.hub, key);
  assert.ok(!r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
  server.close();
  // An outage of the model does not stop an agent either, and recommends nothing.
  installDecisionProfile(r, "http://127.0.0.1:1/systemone");
  await r.call(key, "chat_post", { to, text: "done", kind: "all_done", done: "The release has been confirmed" });
  await review(r.hub, key);
  assert.ok(!r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
  await r.close();
});

test("nothing is recommended while the rule is off or its model is not verified", async () => {
  const r = new Rig();
  const m = say("<@UBOT> explain retention");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  const { url, server } = await provider(true);
  installDecisionProfile(r, url);
  const args = { to: `C1/${m.threadTs}`, text: "Here is the answer", kind: "all_done", done: "The factual question was answered" };
  r.edit((raw) => (raw.automaticDecisions.completion.model = "not-the-verified-model"));
  await r.call(key, "chat_post", args);
  await review(r.hub, key);
  assert.ok(!r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
  r.edit((raw) => (raw.automaticDecisions.completion = { model: "test-jev", enabled: false }));
  await r.call(key, "chat_post", args);
  await review(r.hub, key);
  assert.ok(!r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
  server.close();
  await r.close();
});

test("turning the rule on reviews the done chats no decision has answered, once each", async (t) => {
  const r = new Rig();
  const m = say("<@UBOT> explain retention");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  const thread = () => r.thread("C1", m.threadTs).id;
  const { url, server } = await provider(true);
  t.after(() => server.close());
  installDecisionProfile(r, url);
  // Done while the rule was off: nothing looked at it.
  r.edit((raw) => (raw.automaticDecisions.completion.enabled = false));
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "It controls retention.", kind: "all_done", done: "Explained the setting" });
  r.claude.last().complete();
  await settle();
  await review(r.hub, key);
  assert.ok(!r.store.archiveSuggested(thread()));
  assert.equal(r.store.recentDecisions().length, 0);
  // Turned on: it is reviewed then, without the agent ending another turn.
  r.edit((raw) => (raw.automaticDecisions.completion.enabled = true));
  await reviewUndecided(r.hub);
  assert.ok(r.store.archiveSuggested(thread()));
  assert.equal(r.store.recentDecisions().length, 1);
  // A chat already answered as it stands is not asked about again.
  await reviewUndecided(r.hub);
  assert.equal(r.store.recentDecisions().length, 1);
  await r.close();
});

test("a review waiting for old checks rechecks the rule and model before scanning chats again", async () => {
  const r = new Rig();
  const m = say("<@UBOT> explain retention");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "Done", kind: "all_done", done: "Explained retention" });
  r.claude.last().complete();
  await settle();
  installDecisionProfile(r, "http://127.0.0.1:1/systemone");
  const ready = Promise.withResolvers<void>(), entered = Promise.withResolvers<void>();
  const readyAgain = Promise.withResolvers<void>(), enteredAgain = Promise.withResolvers<void>();
  let scans = 0;
  const liveSessions = r.store.liveSessions.bind(r.store);
  r.store.liveSessions = () => { scans++; return liveSessions(); };
  r.store.lastDecision = () => { throw new DecisionSessionsUnavailable(); };
  r.store.prepareDecisionSessions = async () => { entered.resolve(); await ready.promise; };
  try {
    const sweep = reviewUndecided(r.hub);
    await entered.promise;
    assert.equal(scans, 1);
    r.edit((raw) => { raw.automaticDecisions.completion.enabled = false; });
    ready.resolve();
    await sweep;
    assert.equal(scans, 1);

    r.edit((raw) => { raw.automaticDecisions.completion.enabled = true; });
    r.store.prepareDecisionSessions = async () => { enteredAgain.resolve(); await readyAgain.promise; };
    const requested = startReview(r.hub);
    await enteredAgain.promise;
    r.edit((raw) => { raw.profiles[0].enabled = false; });
    readyAgain.resolve();
    assert.equal(await requested, null);
    assert.equal(scans, 2);
  } finally { ready.resolve(); readyAgain.resolve(); await r.close(); }
});

test("a review can use a decision in the bounded tail while the old lookup is preparing", async (t) => {
  const r = new Rig();
  const m = say("<@UBOT> explain retention");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "Done", kind: "all_done", done: "Explained retention" });
  r.claude.last().complete();
  await settle();
  const { url, server } = await provider(true);
  t.after(() => server.close());
  installDecisionProfile(r, url);
  r.store.recordDecision(key, { purpose: "archive", policyAt: 0, result: null, error: "an earlier failure" });
  r.store.decisionSessionsReady = () => false;
  r.store.prepareDecisionSessions = async () => { throw new Error("the bounded tail should answer"); };
  try {
    await reviewUndecided(r.hub);
    assert.ok(r.store.archiveSuggested(r.thread("C1", m.threadTs).id));
    assert.equal(r.store.recentDecisions().length, 2);
  } finally { await r.close(); }
});

test("the archive policy decides by the option picked; an agent changing it is kept by its session and asks again", async (t) => {
  const r = new Rig();
  const m = say("<@UBOT> make the button blue, show me first");
  await r.accept(m);
  await settle();
  const key = `cl:C1:${m.threadTs}`;
  const thread = () => r.thread("C1", m.threadTs).id;
  const { url, server } = await provider(false);
  t.after(() => server.close());
  installDecisionProfile(r, url);
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "Branch blue-button is up for you to look at.", kind: "all_done", done: "The branch is pushed" });
  r.claude.last().complete();
  await settle();
  await review(r.hub, key);
  // Picked: awaiting review, which the default policy does not count as archive.
  assert.ok(!r.store.archiveSuggested(thread()));
  const decided = r.store.lastDecision(key);
  assert.deepEqual(decided.option, { id: "awaiting_review", name: "等人看结果", archive: false });
  assert.equal(decided.policyAt, 0);
  const [tool] = archiveTools(r.hub);
  const read = JSON.parse(await tool!.run(key, {}));
  assert.deepEqual(read, DEFAULT_POLICY);
  await assert.rejects(tool!.run(key, { options: [{ name: "只有一个", rubric: "", archive: true }] }), /2 到 20/);
  const options = read.options.map((o: Json) => (o.id === "awaiting_review" ? { ...o, archive: true } : o));
  const said = await tool!.run(key, { options });
  assert.match(said, /「等人看结果」改成推荐归档/);
  assert.equal(await tool!.run(key, { options }), "Nothing changed: the policy is already so.");
  const saved = r.store.archivePolicy()!;
  assert.deepEqual(saved.change.by, { kind: "agent", session: key });
  // Under the new policy the chat is asked about again, and now recommended.
  await reviewUndecided(r.hub);
  assert.ok(r.store.archiveSuggested(thread()));
  assert.equal(r.store.lastDecision(key).policyAt, saved.change.id);
  await r.close();
});

// ── the tools beside the hub's ──

test("station_* reach the transport, pretty-printed; adb_devices and feedback_send as the Rust says them", async () => {
  const calls: [string, string, Json][] = [];
  const tools = remoteTools({
    tool: async (name: string, session: string, args: Json) => {
      calls.push([name, session, args]);
      return { ok: true, stations: [] };
    },
  } as unknown as Remote);
  assert.equal(await tools[0]!.run("s", {}), JSON.stringify({ ok: true, stations: [] }, null, 2));
  assert.deepEqual(calls, [["station_list", "s", {}]]);
  const none = await adbTools(() => [])[0]!.run("s", {});
  assert.ok(none.startsWith("No phone is shared") && none.includes("phone_use") && !none.includes("http"));
  const one = await adbTools(() => [{ serial: "127.0.0.1:37123", adb: "connected" }])[0]!.run("s", {});
  assert.ok(one.includes("127.0.0.1:37123") && one.includes("adb -s <serial>") && one.includes("phone_use") && !one.includes("http"));
  const r = new Rig();
  const [key] = newSession(r.hub, web("local"));
  const sent: Json[] = [];
  const feedback = feedbackTools(r.store, () => "https://x/o/1", () => async (report) => (sent.push(report), { number: 7 }))[0]!;
  assert.equal(await feedback.run(key, { to: "CHAT/1.1", title: "chat_post fails", body: "it said 500", area: "station", reporter: "Ada" }), "Sent to the still.fail team as FB-7.");
  assert.deepEqual([sent[0].area, sent[0].context.session, sent[0].context.thread, sent[0].context.link], ["station", key, "CHAT/1.1", "https://x/o/1"]);
  await assert.rejects(feedbackTools(r.store, () => null, () => null)[0]!.run(key, { title: "a", body: "b" }), /not connected to still.fail cloud/);
  await r.close();
});

test("a sender's first line does not construct a summary or count the chat's growing history", async () => {
  const r = new Rig({ link: true });
  try {
    const a = say("<@UBOT> ship it\nand tell me");
    await r.accept(a);
    await settle();
    const key = sessionKey("cl", "C1", a.threadTs);
    const thread = r.store.latestThread(key)!.thread.id;
    const insert = r.store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'agent', ?, 'later', ?)");
    r.store.db.exec("BEGIN");
    for (let n = 100; n < 2_100; n++) insert.run(thread, n, key, n);
    r.store.db.exec("COMMIT");
    const listThreads = r.store.listThreads.bind(r.store);
    let lists = 0;
    r.store.listThreads = (...args) => { lists++; return listThreads(...args); };
    assert.equal(sender(r.hub, key)[0], "ship it");
    assert.equal(lists, 0, "the title lookup does not count unread messages or build a thread summary");
  } finally {
    await r.close();
  }
});

test("a chat is headed as the chat list calls it: its name, the agent's, else 新对话; never its first message", async () => {
  const r = new Rig({ link: true });
  const a = say("<@UBOT> ship it\nand tell me");
  await r.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  // A Slack thread: by the first line said in it.
  assert.equal(sender(r.hub, keyA)[0], "ship it");
  await r.call(keyA, "chat_create", { key: "android", text: "看 [一起排查](https://x/o/1) 要排队", title: "安卓构建" });
  const child = r.store.openedBy(keyA)[0]!.child;
  const thread = r.store.homeChat(child)!;
  assert.equal(sender(r.hub, child)[0], "安卓构建");
  // (chat_create names its session too)
  r.store.setThreadTitle(thread.id, null);
  r.store.setTitle(child, null);
  assert.equal(sender(r.hub, child)[0], untitled());
  r.store.setAutoTitle(thread.id, "安卓发版", true);
  assert.equal(sender(r.hub, child)[0], "安卓发版");
  await r.close();
});

test("a login card in Slack: only for a login here waiting for its page's code; its field goes to that login alone", async () => {
  const r = new Rig();
  Object.assign(r.chat, { cards: true, loginCards: true });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const to = `C1/${m.threadTs}`;
  const answered: [string, string, unknown][] = [];
  const pages: Record<string, CardPage> = {
    l1: { url: "https://accounts.google.com/o/oauth2/auth?x=1", domain: "accounts.google.com", paste: true },
    l3: { url: "https://github.com/login/device", domain: "github.com", code: "ABCD-1234", paste: false },
  };
  r.hub.logins = { page: (id) => pages[id] ?? null, answer: (id, code, by) => void answered.push([id, code, by]) };
  // A login at no such step (a loopback one): no card here.
  assert.match(await r.refused(key, "chat_post", { to, text: "登录", card: { type: "login", login: "l2" } }), /gives a device code, or waits for a code/);
  await r.call(key, "chat_post", { to, text: "登录 gh", card: { type: "login", login: "l3" } });
  await r.call(key, "chat_post", { to, text: "登录 gcloud", card: { type: "login", login: "l1" } });
  // The platform is given the page; the chat keeps the card without it.
  assert.deepEqual(r.chat.carried.slice(-2), [{ type: "login", login: "l3", page: pages.l3 }, { type: "login", login: "l1", page: pages.l1 }]);
  const thread = r.store.threadAt(r.hub.surface("cl"), "C1", m.threadTs)!;
  assert.deepEqual(r.store.messagesBefore(thread.id, null, 2).map((x) => r.store.cardAt(thread.id, x.ts)), [{ type: "login", login: "l3" }, { type: "login", login: "l1" }]);
  const posted = r.store.messagesBefore(thread.id, null, 1)[0]!.ts;
  // Pressed on any other message: refused, nothing handed over.
  await assert.rejects(r.hub.receive("cl", { type: "loginCode", channel: "C1", threadTs: m.threadTs, ts: m.ts, user: "U1", code: "c0" }), /no login card/);
  await r.hub.receive("cl", { type: "loginCode", channel: "C1", threadTs: m.threadTs, ts: posted, user: "U1", code: "c1" });
  assert.deepEqual(answered.map(([id, code]) => [id, code]), [["l1", "c1"]]);
  assert.equal(r.store.messagesBefore(thread.id, null, 1)[0]!.ts, posted, "the code is no message of the thread");
  await settle();
  await r.close();
});

test("a chat an agent opens told no effort runs the one its starter uses most with its model there, else the model's", async () => {
  const r = new Rig({ link: true });
  const a = say("<@UBOT> think hard");
  await r.accept(a);
  await settle();
  const keyA = sessionKey("cl", "C1", a.threadTs);
  // Never named one: the model's own.
  await r.call(keyA, "chat_create", { key: "first", text: "first" });
  const first = r.session(r.store.openedBy(keyA)[0]!.child);
  assert.equal(first.effort ?? null, null);
  // Their chats on that runtime and model ran at high, more than at low: high.
  const ran = (effort: string, keys: string[]) => {
    for (const k of keys) r.store.db.prepare("UPDATE sessions SET runtime = ?, model = ?, effort = ? WHERE key = ?").run(first.runtime, first.model ?? null, effort, k);
  };
  ran("high", [keyA, first.key]);
  await r.call(keyA, "chat_create", { key: "second", text: "second" });
  const second = r.session(r.store.openedBy(keyA)[1]!.child);
  assert.equal(second.effort, "high");
  // One named stays as named.
  await r.call(keyA, "chat_create", { key: "third", text: "third", effort: "low" });
  assert.equal(r.session(r.store.openedBy(keyA)[2]!.child).effort, "low");
  // One no profile here runs any longer: the model's own, not refused.
  ran("no-such-effort", [keyA, first.key, second.key]);
  r.store.setOpenedState("", first.key, "all_done");
  r.store.setOpenedState("", second.key, "all_done");
  await r.call(keyA, "chat_create", { key: "fourth", text: "fourth" });
  assert.equal(r.session(r.store.openedBy(keyA)[3]!.child).effort ?? null, null);
  await r.close();
});
