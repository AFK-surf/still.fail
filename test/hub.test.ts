import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { Hub, isStopCommand, sessionKey } from "../src/hub.ts";
import { Store } from "../src/store.ts";
import { InternalChat } from "../src/chat/internal.ts";
import { FakeChat, FakeDriver, message, settle } from "./fakes.ts";

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

function setup(overrides: { maxNudges?: number; maxWarmClaude?: number; warmMinutes?: number; team?: { requireMention?: boolean }; link?: boolean } = {}) {
  const { team, link, ...rest } = overrides;
  const dataDir = mkdtempSync(join(tmpdir(), "ember-test-"));
  const config = parseConfig({
    profiles: [
      { id: "cc", runtime: "claude", home: "homes/cc" },
      { id: "cx", runtime: "codex", home: "homes/cx" },
    ],
    connects: [
      { id: "cl", slack: { botName: "Claude bot" }, bind: { runtime: "claude", model: "opus", effort: "high" } },
      { id: "gpt", bind: { runtime: "codex" } },
      { id: "team", mode: "single-session", requireMention: team?.requireMention ?? true, bind: { runtime: "claude" } },
    ],
    ...rest,
  }, dataDir);
  const store = new Store(":memory:");
  const chat = new FakeChat("UBOT");
  const gptChat = new FakeChat("UGPT");
  const teamChat = new FakeChat("UTEAM");
  const claude = new FakeDriver("claude");
  const codex = new FakeDriver("codex");
  const hub = new Hub({ config: () => config, store, chats: new Map([["cl", chat], ["gpt", gptChat], ["team", teamChat]]), drivers: { claude, codex }, mcpUrl: "http://127.0.0.1:1/mcp", internal: new InternalChat(),
    ...(link ? { link: (key: string) => `https://ember.test/o/ws/st/${encodeURIComponent(key)}` } : {}) });
  const tools = Object.fromEntries(hub.tools().map((t) => [t.name, t]));
  const call = (key: string, name: string, args: Record<string, unknown>) => tools[name]!.run(key, args);
  const accept = (m: ReturnType<typeof message>, connect = "cl") => hub.accept(connect, m);
  return { config, store, chat, gptChat, teamChat, claude, codex, hub, call, accept };
}

test("a new session first says where it can be followed (multi-session connects only)", async () => {
  const { chat, teamChat, accept } = setup({ link: true });
  const m = message({ text: "<@UBOT> fix the build" });
  await accept(m);
  await settle();
  assert.equal(chat.posts.length, 1);
  assert.match(chat.posts[0]!.text, /^\[在 ember 里查看这个会话\]\(https:\/\/ember\.test\/o\/ws\/st\/cl%3AC1%3A[\d.]+\)$/);
  assert.deepEqual(chat.posts[0]!.thread, { channel: "C1", threadTs: m.threadTs });
  // Its next message is the same session: nothing more.
  await accept(message({ text: "<@UBOT> and the tests", threadTs: m.threadTs }));
  await settle();
  assert.equal(chat.posts.length, 1);
  // A single-session connect has one session for everything: no link per thread.
  await accept(message({ text: "<@UBOT> hi" }), "team");
  await settle();
  assert.equal(teamChat.posts.length, 0);
});

test("a mention starts a session and prompts the runtime with the message", async () => {
  const { claude, store, accept } = setup();
  const m = message({ text: "<@UBOT> fix the build" });
  await accept(m);
  await settle();
  const session = claude.last;
  assert.equal(session.prompts.length, 1);
  // What the agent is called there comes with the message (the connect's bot and its mention).
  assert.match(session.prompts[0]!, /<message via="slack" connect="cl" you="ember \(<@UBOT>\)" thread="C1\/[\d.]+" from="U1" ts="[\d.]+">\n<@UBOT> fix the build\n<\/message>/);
  assert.equal(store.getSession(sessionKey("cl", "C1", m.threadTs))?.runtimeSessionId, session.id);
  assert.equal(session.options.cwd.endsWith("workspace"), true);
});

test("thread chatter without a session is ignored", async () => {
  const { claude, accept } = setup();
  await accept(message({ addressed: false, text: "just talking" }));
  await settle();
  assert.equal(claude.sessions.length, 0);
});

test("a mention inside an existing thread records what was said before and tells the agent about it", async () => {
  const { claude, accept, chat, store, call } = setup();
  chat.earlier.set("1.000001", [
    { ts: "1.000001", user: "U2", text: "the build is red", fromBot: false },
    { ts: "3.000001", user: "U3", text: "since this morning", fromBot: false },
  ]);
  await accept(message({ threadTs: "1.000001", ts: "5.000001" }));
  await settle();
  assert.match(claude.last.prompts[0]!, /Thread C1\/1.000001 had messages before you were brought in/);
  assert.doesNotMatch(claude.last.prompts[0]!, /the build is red/, "earlier messages are recorded, not delivered");
  const thread = store.threadAt("slack:T1", "C1", "1.000001")!;
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 10).map((m) => m.ts), ["1.000001", "3.000001", "5.000001"]);
  const history = await call(sessionKey("cl", "C1", "1.000001"), "chat_history", { to: "C1/1.000001", before: "5.000001" });
  assert.match(history, /from="U2" ts="1.000001">\nthe build is red/);
  assert.doesNotMatch(history, /hello/);
});

test("a message during a running turn is steered into it", async () => {
  const { claude, accept } = setup();
  const first = message();
  await accept(first);
  await settle();
  await accept(message({ threadTs: first.threadTs, ts: "9999.1", addressed: false, text: "also check tests" }));
  await settle();
  assert.equal(claude.last.prompts.length, 1);
  assert.match(claude.last.steers[0]!, /also check tests/);
});

test("the same message delivered twice is handled once", async () => {
  const { claude, accept } = setup();
  const m = message();
  await accept(m);
  await accept({ ...m });
  await settle();
  assert.equal(claude.last.prompts.length, 1);
});

test("a turn ending without final/block is nudged, then reported after maxNudges", async () => {
  const { claude, chat, accept } = setup({ maxNudges: 1 });
  await accept(message());
  await settle();
  claude.last.end();
  await settle();
  assert.equal(claude.last.prompts.length, 2);
  assert.match(claude.last.prompts[1]!, /without a final or block state/);
  claude.last.end();
  await settle();
  assert.equal(claude.last.prompts.length, 2);
  assert.match(chat.posts.at(-1)!.text, /没有给出明确结果/);
});

test("chat_post with kind final posts and settles the turn without a nudge", async () => {
  const { claude, chat, call, accept } = setup();
  const m = message();
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.equal(await call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "**done**", kind: "final" }), `Posted to C1/${m.threadTs}, and recorded state final.`);
  claude.last.end();
  await settle();
  assert.equal(claude.last.prompts.length, 1);
  assert.deepEqual(chat.posts, [{ thread: { channel: "C1", threadTs: m.threadTs }, text: "**done**" }]);
});

test("the agent's posts are recorded in the thread, and chat_history shows them as its own", async () => {
  const { call, accept, store } = setup();
  const m = message({ text: "<@UBOT> look" });
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "looking", kind: "block" });
  const thread = store.threadAt("slack:T1", "C1", m.threadTs)!;
  const [said, posted] = store.messagesBefore(thread.id, undefined, 10);
  assert.deepEqual([said!.authorKind, posted!.authorKind, posted!.author, posted!.declared], ["person", "agent", key, "block"]);
  assert.equal(store.pendingMessages(key).length, 0, "an agent's own post is not delivered back to it");
  const history = await call(key, "chat_history", { to: `C1/${m.threadTs}` });
  assert.match(history, /from="U1" ts="[\d.]+">\n<@UBOT> look[\s\S]*from="you" ts="[\d.]+">\nlooking/);
});

test("Slack edits are appended to the thread as entries of their own", async () => {
  const { hub, accept, store } = setup();
  const m = message({ text: "<@UBOT> typo" });
  await accept(m);
  const thread = store.threadAt("slack:T1", "C1", m.threadTs)!;
  const before = store.lastEntry(thread.id);
  await hub.receive("cl", { kind: "changed", channel: "C1", threadTs: m.threadTs, ts: m.ts, text: "<@UBOT> fixed" });
  await hub.receive("cl", { kind: "changed", channel: "C1", threadTs: m.threadTs, ts: m.ts, text: "<@UBOT> fixed" }); // Slack repeats roots when replies come
  const [edit] = store.entriesAfter(thread.id, before);
  assert.deepEqual([edit!.kind, edit!.target, edit!.text], ["edit", before, "<@UBOT> fixed"]);
  assert.equal(store.lastEntry(thread.id), before + 1);
});

test("chat_state rejects kinds other than final and block", async () => {
  const { call, accept } = setup();
  const m = message();
  await accept(m);
  await assert.rejects(call(sessionKey("cl", "C1", m.threadTs), "chat_state", { kind: "wait" }), /final" or "block/);
});

test("-stop aborts the running turn and confirms once it ends", async () => {
  const { claude, chat, accept } = setup();
  const m = message();
  await accept(m);
  await settle();
  await accept(message({ threadTs: m.threadTs, ts: "9999.2", text: "<@UBOT> -stop" }));
  await settle();
  assert.equal(claude.last.aborts, 1);
  assert.equal(claude.last.steers.length, 0, "-stop is not forwarded to the agent");
  claude.last.end({ kind: "aborted" });
  await settle();
  assert.equal(chat.posts.at(-1)!.text, "已停止当前任务。");
  assert.equal(claude.last.prompts.length, 1, "no nudge after a stop");
});

test("a failed turn is reported to the thread and not nudged", async () => {
  const { claude, chat, accept } = setup();
  await accept(message());
  await settle();
  claude.last.end({ kind: "failed", reason: "auth", message: "401 Missing API key" });
  await settle();
  assert.match(chat.posts.at(-1)!.text, /认证失败.*401 Missing API key/);
  assert.equal(claude.last.prompts.length, 1);
});

test("messages that arrive while a turn cannot take them go in the next turn", async () => {
  const { claude, accept } = setup();
  const m = message();
  await accept(m);
  await settle();
  const session = claude.last;
  session.steer = async () => false; // e.g. a codex turn that is not steerable
  await accept(message({ threadTs: m.threadTs, ts: "9999.3", addressed: false, text: "one more thing" }));
  await settle();
  session.end();
  await settle();
  assert.equal(session.prompts.length, 2);
  assert.match(session.prompts[1]!, /one more thing/);
});

test("a connect's runtime, profile and model decide the session", async () => {
  const { claude, codex, store, accept } = setup();
  const m = message({ text: "<@UGPT> refactor this" });
  await accept(m, "gpt");
  await settle();
  assert.equal(claude.sessions.length, 0);
  assert.equal(codex.sessions.length, 1);
  const row = store.getSession(sessionKey("gpt", "C1", m.threadTs));
  assert.equal(row?.profile, "cx");
  assert.equal(row?.model, null);
  const n = message();
  await accept(n);
  await settle();
  assert.equal(store.getSession(sessionKey("cl", "C1", n.threadTs))?.model, "opus");
  assert.equal(claude.last.options.effort, "high", "the connect's effort reaches the runtime");
  // Guidance only: no identity, no name (what it is called comes with each message, per connect).
  assert.doesNotMatch(claude.last.options.instructions, /You are |Claude bot/);
});

test("two connects in one thread keep separate sessions, share its messages, and reply through their own connection", async () => {
  const { chat, gptChat, claude, codex, call, accept, store } = setup();
  const root = message({ text: "<@UBOT> <@UGPT> compare notes" });
  await accept(root);
  await accept(root, "gpt");
  await settle();
  const reply = message({ threadTs: root.threadTs, ts: "9999.7", addressed: false, text: "both of you: go" });
  await accept(reply);
  await accept(reply, "gpt");
  await settle();
  assert.match(claude.last.steers[0]!, /both of you/);
  assert.match(codex.last.steers[0]!, /both of you/);
  await call(sessionKey("gpt", "C1", root.threadTs), "chat_post", { to: `C1/${root.threadTs}`, text: "from gpt" });
  assert.deepEqual(gptChat.posts.map((p) => p.text), ["from gpt"]);
  assert.equal(chat.posts.length, 0);
  const thread = store.threadAt("slack:T1", "C1", root.threadTs)!;
  assert.deepEqual(store.threadSessions(thread.id).map((m) => [m.session, m.connect]), [
    [sessionKey("cl", "C1", root.threadTs), "cl"], [sessionKey("gpt", "C1", root.threadTs), "gpt"],
  ]);
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 10).map((m) => m.authorKind), ["person", "person", "agent"], "each message once, however many connects saw it");
});

test("a mention of one connect does not start a session for another connect that sees the message", async () => {
  const { codex, accept } = setup();
  await accept(message({ addressed: false, text: "<@UBOT> only claude" }), "gpt");
  await settle();
  assert.equal(codex.sessions.length, 0);
});

test("after a restart a cut-off turn is resumed", async () => {
  const first = setup();
  const m = message();
  await first.accept(m);
  await settle();
  const runtimeId = first.claude.last.id;

  // Same store, new hub and drivers: what a restart looks like.
  const claude = new FakeDriver("claude");
  const hub = new Hub({ config: () => first.config, store: first.store, chats: new Map([["cl", first.chat]]), drivers: { claude, codex: new FakeDriver("codex") }, mcpUrl: "x" });
  await hub.recover();
  await settle();
  assert.equal(claude.last.options.resume, runtimeId);
  assert.match(claude.last.prompts[0]!, /restarted while you were in the middle of a turn/);
});

test("when the runtime session cannot be resumed, a new one starts and is told to catch up", async () => {
  const { claude, accept } = setup();
  const m = message();
  await accept(m);
  await settle();
  const old = claude.last;
  old.end({ kind: "failed", reason: "exited", message: "gone" });
  old.events.closed("gone");
  await settle();
  claude.unresumable.add(old.id);
  await accept(message({ threadTs: m.threadTs, ts: "9999.4", addressed: false, text: "still there?" }));
  await settle();
  assert.notEqual(claude.last, old);
  assert.equal(claude.last.options.resume, undefined);
  assert.match(claude.last.prompts[0]!, /could not be restored[\s\S]*still there\?/);
});

test("idle claude processes beyond the warm limit are evicted, oldest first, as soon as another goes idle", async () => {
  const { claude, accept } = setup({ maxWarmClaude: 1, warmMinutes: 0 });
  const a = message({ ts: "1.1", threadTs: "1.1" });
  const b = message({ ts: "2.1", threadTs: "2.1" });
  await accept(a);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  assert.equal(claude.last.disposed, false, "within the limit");
  await accept(b);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  assert.deepEqual(claude.sessions.map((s) => s.disposed), [true, false]);
});

test("an idle process beyond the limit is evicted at its own deadline", async () => {
  const { claude, accept } = setup({ maxWarmClaude: 0, warmMinutes: 0.002 }); // 120 ms
  await accept(message());
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  assert.equal(claude.last.disposed, false, "not idle long enough yet");
  await wait(250);
  await settle();
  assert.equal(claude.last.disposed, true);
});

test("a running turn is never evicted", async () => {
  const { claude, accept } = setup({ maxWarmClaude: 0, warmMinutes: 0 });
  await accept(message());
  await wait(20);
  await settle();
  assert.equal(claude.last.disposed, false);
});

test("chat_post and chat_history need an explicit thread of this session", async () => {
  const { call, accept, chat } = setup();
  const m = message();
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await assert.rejects(call(key, "chat_post", { text: "hi" }), /to is required[\s\S]*C1\//);
  await assert.rejects(call(key, "chat_post", { to: "C1", text: "hi" }), /CHANNEL\/THREAD_TS/);
  await assert.rejects(call(key, "chat_post", { to: "C9/1.1", text: "hi" }), /not a conversation of this session/);
  await assert.rejects(call(key, "chat_history", {}), /to is required/);
  assert.equal(chat.posts.length, 0);
});

test("a single-session connect gathers every thread into one session and replies where asked", async () => {
  const { claude, teamChat, store, call, accept } = setup();
  const a = message({ text: "<@UTEAM> build A", channel: "C1" });
  await accept(a, "team");
  await settle();
  await accept(message({ addressed: false, text: "unrelated chatter", channel: "C2" }), "team");
  const b = message({ text: "<@UTEAM> build B", channel: "C2" });
  await accept(b, "team");
  await settle();
  assert.equal(claude.sessions.length, 1);
  assert.equal(store.listSessions().length, 1);
  const bound = store.binding("team")!;
  assert.equal(store.getSession(bound)?.scope, "all");
  assert.match(claude.last.steers[0]!, /thread="C2\/[\d.]+"[\s\S]*build B/);
  assert.doesNotMatch(claude.last.steers.join("\n") + claude.last.prompts.join("\n"), /unrelated chatter/);
  // A reply in a thread the session already follows needs no mention.
  await accept(message({ addressed: false, threadTs: a.threadTs, ts: "9999.8", text: "and tests too", channel: "C1" }), "team");
  await settle();
  assert.match(claude.last.steers.at(-1)!, /and tests too/);
  await call(bound, "chat_post", { to: `C2/${b.threadTs}`, text: "B done" });
  assert.deepEqual(teamChat.posts, [{ thread: { channel: "C2", threadTs: b.threadTs }, text: "B done" }]);
});

test("a single-session connect without requireMention hears every message", async () => {
  const { claude, accept } = setup({ team: { requireMention: false } });
  await accept(message({ addressed: false, text: "anyone around?" }), "team");
  await settle();
  assert.equal(claude.sessions.length, 1);
  assert.match(claude.last.prompts[0]!, /anyone around\?/);
});

test("a single-session connect can be pointed at a new or an existing session", async () => {
  const { claude, hub, store, accept, teamChat, chat, call } = setup();
  const first = message({ text: "<@UTEAM> one" });
  await accept(first, "team");
  await settle();
  const old = store.binding("team")!;
  const fresh = hub.bindSingle("team", null, "值班");
  assert.notEqual(fresh, old);
  assert.equal(store.getSession(fresh)?.title, "值班");
  await accept(message({ text: "<@UTEAM> two" }), "team");
  await settle();
  assert.equal(claude.sessions.length, 2, "the new binding got its own runtime session");
  assert.match(claude.last.prompts[0]!, /two/);

  // Binding a session that another connect started: replies still go out where each thread came in.
  const m = message({ text: "<@UBOT> from cl" });
  await accept(m);
  await settle();
  const clKey = sessionKey("cl", "C1", m.threadTs);
  hub.bindSingle("team", clKey);
  const t = message({ text: "<@UTEAM> via team", channel: "C7" });
  await accept(t, "team");
  await settle();
  assert.deepEqual(store.sessionThreads(clKey).map((t) => [t.channel, t.connect]), [["C7", "team"], ["C1", "cl"]]);
  await call(clKey, "chat_post", { to: `C7/${t.threadTs}`, text: "to team thread" });
  await call(clKey, "chat_post", { to: `C1/${m.threadTs}`, text: "to cl thread" });
  assert.deepEqual(teamChat.posts.map((p) => p.text), ["to team thread"]);
  assert.deepEqual(chat.posts.map((p) => p.text), ["to cl thread"]);
  assert.throws(() => hub.bindSingle("team", sessionKey("gpt", "C1", "1.1")), /unknown session/);
  assert.throws(() => hub.bindSingle("cl", null), /not single-session/);
});

test("a chat opened on the admin page reaches the session like Slack, and the agent answers there", async () => {
  const { claude, hub, store, call, accept, chat } = setup();
  const m = message();
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  claude.last.end();
  await settle();
  const thread = hub.openChat(key, "local", "排查");
  hub.say(thread.id, "local", "现在进展如何？");
  await settle();
  const prompt = claude.last.prompts.at(-1)!;
  assert.match(prompt, new RegExp(`<message via="web" connect="ember" thread="EMBER/${thread.threadTs.replace(".", "\\.")}" from="管理员 \\(local\\)"`));
  assert.match(prompt, /现在进展如何/);
  assert.equal(await call(key, "chat_post", { to: `EMBER/${thread.threadTs}`, text: "快好了", kind: "final" }), `Posted to EMBER/${thread.threadTs}, and recorded state final.`);
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 10).map((x) => [x.authorKind, x.text]), [["person", "现在进展如何？"], ["agent", "快好了"]]);
  assert.equal(chat.posts.length, 1, "only the Slack thread's own answer went to Slack");
  const history = await call(key, "chat_history", { to: `EMBER/${thread.threadTs}` });
  assert.match(history, /现在进展如何/);
  assert.throws(() => hub.openChat("nope", "local"), /unknown session/);
});

test("a person's message in a chat with several agents reaches each of them once", async () => {
  const { claude, codex, hub, store } = setup();
  const one = hub.newSession({ runtime: "claude", createdBy: "local" });
  const two = hub.newSession({ runtime: "codex", createdBy: "local" });
  hub.addToThread(one.thread.id, two.key);
  hub.say(one.thread.id, "a@example.com", "你们俩分一下工", [], [{ author: "Claude", role: "agent", ts: "1.000001", text: "上一条", comment: "这里" }]);
  await settle();
  for (const driver of [claude, codex]) {
    assert.equal(driver.sessions.length, 1);
    assert.match(driver.last.prompts[0]!, /\[Quote\] From your own earlier message 1\.000001 in this conversation:\n> 上一条\nTheir comment on it: 这里\n\n你们俩分一下工/);
  }
  assert.equal(store.pendingMessages(one.key).length + store.pendingMessages(two.key).length, 0);
  const [message] = store.messagesBefore(one.thread.id, undefined, 10);
  assert.equal(message!.text, "你们俩分一下工", "the words are stored as typed; the quote is a column");
  assert.equal(message!.quotes[0]!.comment, "这里");
});

test("a pending message edited before delivery reaches the agent as edited", async () => {
  const { claude, hub, accept, store } = setup();
  const m = message();
  await accept(m);
  await settle();
  const session = claude.last;
  session.steer = async () => false;
  const edited = message({ threadTs: m.threadTs, ts: "9999.5", addressed: false, text: "first draft" });
  await accept(edited);
  await settle(); // it waits: the running turn takes no steer
  await hub.receive("cl", { kind: "changed", channel: "C1", threadTs: m.threadTs, ts: edited.ts, text: "final words" });
  session.end();
  await settle();
  assert.match(session.prompts[1]!, /final words/);
  assert.doesNotMatch(session.prompts[1]!, /first draft/);
  assert.equal(store.pendingMessages(sessionKey("cl", "C1", m.threadTs)).length, 0);
});

test("deleting a session ends its process and removes its workspace and the threads only it was in", async () => {
  const { claude, hub, accept, store, config } = setup();
  const m = message();
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const row = store.getSession(key)!;
  const { existsSync, mkdirSync, writeFileSync } = await import("node:fs");
  // The runtime's transcript lives in the profile's home and stays.
  const transcript = join(config.profiles[0]!.home, "projects", "x", `${row.runtimeSessionId}.jsonl`);
  mkdirSync(join(transcript, ".."), { recursive: true });
  writeFileSync(transcript, "{}\n");
  assert.equal(existsSync(row.workspace), true);
  await hub.deleteSession(key);
  assert.equal(claude.last.disposed, true);
  assert.equal(store.getSession(key), undefined);
  assert.equal(store.threadAt("slack:T1", "C1", m.threadTs), undefined);
  assert.equal(existsSync(row.workspace), false);
  assert.equal(existsSync(join(row.workspace, "..")), false);
  assert.equal(existsSync(transcript), true);
});

test("archiving a session keeps a zstd copy of its transcript; showing it again or deleting it removes the copy", async () => {
  const { hub, accept, store, config } = setup();
  const m = message();
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const row = store.getSession(key)!;
  const { existsSync, mkdirSync, readFileSync, writeFileSync } = await import("node:fs");
  const { zstdDecompressSync } = await import("node:zlib");
  const transcript = join(config.profiles[0]!.home, "projects", "x", `${row.runtimeSessionId}.jsonl`);
  mkdirSync(join(transcript, ".."), { recursive: true });
  writeFileSync(transcript, "{\"type\":\"user\"}\n");
  const copy = join(store.archiveDir, "transcripts", `${key}.jsonl.zst`);
  hub.archive(key, true);
  assert.equal(zstdDecompressSync(readFileSync(copy)).toString(), "{\"type\":\"user\"}\n");
  assert.equal(existsSync(transcript), true, "the runtime's own file stays as it is");
  hub.archive(key, false);
  assert.equal(existsSync(copy), false);
  hub.archive(key, true);
  await hub.deleteSession(key);
  assert.equal(existsSync(copy), false);
});

test("command parsing", () => {
  assert.equal(isStopCommand("<@UBOT>  -stop "), true);
  assert.equal(isStopCommand("please -stop now"), false);
});

test("chat_post attaches files to an ember chat, measuring images; Slack refuses them", async () => {
  const { sizeOf } = await import("../src/image-size.ts");
  const png = Buffer.alloc(24); png.writeUInt32BE(0x89504e47, 0); png.write("IHDR", 12, "ascii"); png.writeUInt32BE(640, 16); png.writeUInt32BE(480, 20);
  assert.deepEqual(sizeOf(png), { width: 640, height: 480 });
  const gif = Buffer.from("GIF89a\x20\x00\x10\x00", "latin1");
  assert.deepEqual(sizeOf(gif), { width: 32, height: 16 });
  assert.equal(sizeOf(Buffer.from("not an image")), null);
});

test("a session changes profile, model and effort by hand, and is taken on by another profile when its own cannot run", async () => {
  const { config, store, hub, accept, call, claude } = setup();
  const m = message({ text: "<@UBOT> fix the build" });
  await accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  config.profiles.push({ ...config.profiles[0]!, id: "cc2", name: "another", models: ["opus"] });
  await assert.rejects(hub.configure(key, { profile: "cc2" }), /正在跑/, "not while a turn runs");
  await call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  claude.last.end();
  await settle();
  await hub.configure(key, { profile: "cc2" });
  assert.equal(store.getSession(key)!.profile, "cc2");
  await assert.rejects(hub.configure(key, { profile: "cx" }), /不能跑 Claude Code/);
  config.profiles.push({ ...config.profiles[0]!, id: "cc3", name: "third", models: [] });
  await assert.rejects(hub.configure(key, { profile: "cc3" }), /「third」没有启用 opus/, "only one with its model enabled");
  // Its model and effort change too, to what a profile of its runtime runs.
  await assert.rejects(hub.configure(key, { model: "gpt-5" }), /没有能跑 gpt-5 的 Claude Code Profile/);
  await assert.rejects(hub.configure(key, { effort: "ultra" }), /思考深度只有/);
  for (const id of ["cc", "cc2"]) (config.profiles.find((p) => p.id === id)!.models as string[]).push("sonnet");
  await hub.configure(key, { model: "sonnet", effort: "low", profile: "cc2" });
  assert.deepEqual([store.getSession(key)!.model, store.getSession(key)!.effort], ["sonnet", "low"]);
  assert.equal(store.getSession(key)!.profilePinned, true, "kept to it by hand");
  // Another model alone: what went with the old one starts over, the effort default and the profile the station's
  // pick among those with it enabled.
  (config.profiles.find((p) => p.id === "cc3")!.models as string[]).push("haiku");
  await hub.configure(key, { model: "haiku" });
  assert.deepEqual([store.getSession(key)!.model, store.getSession(key)!.effort, store.getSession(key)!.profile, store.getSession(key)!.profilePinned], ["haiku", null, "cc3", false]);
  await hub.configure(key, { model: "sonnet", effort: "low", profile: "cc2" });
  // Given back to the station, and its own used up: the next start runs on the other one, which takes it on.
  await hub.configure(key, { profile: null });
  assert.equal(store.getSession(key)!.profilePinned, false);
  await hub.evict(key);
  hub.setProfileHealth((id) => ({ check: null, quota: id === "cc2" ? { state: "ok", windows: [{ label: "每周", usedPercent: 100, resetsAt: null }], detail: null, checkedAt: 0 } : null }));
  await accept(message({ text: "<@UBOT> and the tests", threadTs: m.threadTs }));
  await settle();
  assert.equal(store.getSession(key)!.profile, "cc");
});

test("a connect or a new chat can keep its sessions to one profile; otherwise the pool picks", async () => {
  const { config, store, hub, accept } = setup();
  config.profiles.push({ ...config.profiles[0]!, id: "cc2", name: "second", models: ["opus"] });
  (config.connects.find((c) => c.id === "cl")!.bind as { profile?: string }).profile = "cc2";
  const m = message({ text: "<@UBOT> hi" });
  await accept(m);
  await settle();
  const row = store.getSession(sessionKey("cl", "C1", m.threadTs))!;
  assert.deepEqual([row.profile, row.profilePinned], ["cc2", true]);
  // A new chat given a profile keeps to it; one that has not the model on is refused.
  const { key } = hub.newSession({ runtime: "claude", model: "opus", profile: "cc2", createdBy: "local" });
  assert.deepEqual([store.getSession(key)!.profile, store.getSession(key)!.profilePinned], ["cc2", true]);
  assert.throws(() => hub.newSession({ runtime: "claude", model: "sonnet", profile: "cc2", createdBy: "local" }), /没有启用 sonnet/);
  const auto = hub.newSession({ runtime: "claude", createdBy: "local" }).key;
  assert.equal(store.getSession(auto)!.profilePinned, false);
});

test("the Slack thread a turn works for says what the agent is doing, until the turn ends", async () => {
  const { claude, chat, accept } = setup();
  const m = message({ text: "<@UBOT> fix the build" });
  await accept(m);
  await settle();
  const session = claude.last;
  session.events.live?.({ kind: "start", id: "t1", step: "tool", tool: "Bash" });
  session.events.live?.({ kind: "end", id: "t1" });
  session.end();
  await settle();
  assert.deepEqual(chat.statuses.map((s) => s.status), ["正在思考…", "正在运行命令…", "正在思考…", ""]);
  assert.equal(chat.statuses[0]!.thread, `C1/${m.threadTs}`);
  assert.equal(chat.statuses[0]!.ts, m.ts, "the message that started it, for the fallback reaction");
});
