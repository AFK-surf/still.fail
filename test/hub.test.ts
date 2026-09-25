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

function setup(overrides: { maxNudges?: number; maxWarmClaude?: number; warmMinutes?: number; team?: { requireMention?: boolean } } = {}) {
  const { team, ...rest } = overrides;
  const dataDir = mkdtempSync(join(tmpdir(), "ember-test-"));
  const config = parseConfig({
    profiles: [
      { id: "cc", runtime: "claude", home: "homes/cc" },
      { id: "cx", runtime: "codex", home: "homes/cx" },
    ],
    connects: [
      { id: "cl", name: "Claude bot", bind: { runtime: "claude", profiles: ["cc"], model: "opus" } },
      { id: "gpt", bind: { runtime: "codex", profiles: ["cx"] } },
      { id: "team", mode: "single-session", requireMention: team?.requireMention ?? true, bind: { runtime: "claude", profiles: ["cc"] } },
    ],
    ...rest,
  }, dataDir);
  const store = new Store(":memory:");
  const chat = new FakeChat("UBOT");
  const gptChat = new FakeChat("UGPT");
  const teamChat = new FakeChat("UTEAM");
  const claude = new FakeDriver("claude");
  const codex = new FakeDriver("codex");
  const hub = new Hub({ config: () => config, store, chats: new Map([["cl", chat], ["gpt", gptChat], ["team", teamChat]]), drivers: { claude, codex }, mcpUrl: "http://127.0.0.1:1/mcp", internal: new InternalChat(store) });
  const tools = Object.fromEntries(hub.tools().map((t) => [t.name, t]));
  const call = (key: string, name: string, args: Record<string, unknown>) => tools[name]!.run(key, args);
  const accept = (m: ReturnType<typeof message>, connect = "cl") => hub.accept(connect, m);
  return { config, store, chat, gptChat, teamChat, claude, codex, hub, call, accept };
}

test("a mention starts a session and prompts the runtime with the message", async () => {
  const { claude, store, accept } = setup();
  const m = message({ text: "<@UBOT> fix the build" });
  await accept(m);
  await settle();
  const session = claude.last;
  assert.equal(session.prompts.length, 1);
  assert.match(session.prompts[0]!, /<message via="slack" connect="cl" thread="C1\/[\d.]+" from="U1" ts="[\d.]+">\n<@UBOT> fix the build\n<\/message>/);
  assert.equal(store.getSession(sessionKey("cl", "C1", m.threadTs))?.runtimeSessionId, session.id);
  assert.equal(session.options.cwd.endsWith("workspace"), true);
});

test("thread chatter without a session is ignored", async () => {
  const { claude, accept } = setup();
  await accept(message({ addressed: false, text: "just talking" }));
  await settle();
  assert.equal(claude.sessions.length, 0);
});

test("a mention inside an existing thread tells the agent about earlier messages", async () => {
  const { claude, accept } = setup();
  await accept(message({ threadTs: "1.000001", ts: "5.000001" }));
  await settle();
  assert.match(claude.last.prompts[0]!, /Thread C1\/1.000001 had messages before you were brought in/);
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
  assert.match(claude.last.options.instructions, /You are Claude bot/);
});

test("two connects in one thread keep separate sessions and reply through their own connection", async () => {
  const { chat, gptChat, claude, codex, call, accept } = setup();
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

test("idle claude processes beyond the warm limit are evicted, oldest first", async () => {
  const { hub, claude, accept } = setup({ maxWarmClaude: 1, warmMinutes: 0 });
  const a = message({ ts: "1.1", threadTs: "1.1" });
  const b = message({ ts: "2.1", threadTs: "2.1" });
  await accept(a);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  await accept(b);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  hub.evictIdle(Date.now() + 1000);
  await settle();
  assert.deepEqual(claude.sessions.map((s) => s.disposed), [true, false]);
});

test("a running turn is never evicted", async () => {
  const { hub, claude, accept } = setup({ maxWarmClaude: 0, warmMinutes: 0 });
  await accept(message());
  await settle();
  hub.evictIdle(Date.now() + 10_000_000);
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
  assert.equal(store.listInbound(clKey).length, 2);
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
  await hub.sayInChat(thread, "local", "现在进展如何？");
  await settle();
  const prompt = claude.last.prompts.at(-1)!;
  assert.match(prompt, new RegExp(`<message via="web" connect="ember" thread="EMBER/${thread.replace(".", "\\.")}" from="管理员 \\(local\\)"`));
  assert.match(prompt, /现在进展如何/);
  assert.equal(await call(key, "chat_post", { to: `EMBER/${thread}`, text: "快好了", kind: "final" }), `Posted to EMBER/${thread}, and recorded state final.`);
  assert.deepEqual(store.chatMessages(thread).map((x) => [x.role, x.text]), [["person", "现在进展如何？"], ["agent", "快好了"]]);
  assert.equal(chat.posts.length, 1, "only the Slack thread's own answer went to Slack");
  const history = await call(key, "chat_history", { to: `EMBER/${thread}` });
  assert.match(history, /现在进展如何/);
  assert.throws(() => hub.openChat("nope", "local"), /unknown session/);
});

test("command parsing", () => {
  assert.equal(isStopCommand("<@UBOT>  -stop "), true);
  assert.equal(isStopCommand("please -stop now"), false);
});
