// A session's context by hand (SessionActor compact, clear; `-compact`, `-clear` in a thread; POST
// /sessions/:key/compact, /clear): compacted between turns as a turn of the runtime's own, cleared to a new runtime
// session the next turn starts.
import assert from "node:assert/strict";
import { test } from "node:test";
import { usageNow } from "../src/read/usage.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { configure } from "../src/sessions/lifecycle.ts";
import { Rig, message, reply, settle } from "./hub-fakes.ts";

/// A session whose first turn ended done.
async function done(r: Rig) {
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  r.claude.last().complete();
  await settle();
  return { m, key, session: r.claude.last() };
}

test("-compact compacts between turns, holds what comes meanwhile, and says so once done, without a nudge", async () => {
  const r = new Rig();
  const { m, key, session } = await done(r);
  await r.accept(reply(m, "9999.2", "<@UBOT> -compact", { addressed: true }));
  await settle();
  assert.equal(session.compactions, 1);
  assert.equal(session.prompts.length, 1, "-compact is not given to the agent");
  assert.equal(r.session(key).running, true, "shown at work meanwhile");
  // Said meanwhile: it waits for the compaction, not steered into it.
  await r.accept(reply(m, "9999.3", "and then the tests"));
  await settle();
  assert.deepEqual(session.steers, []);
  assert.equal(session.prompts.length, 1);
  session.complete();
  await settle();
  assert.ok(r.chat.texts().includes("已压缩上下文"), r.chat.texts().join("\n"));
  assert.equal(session.prompts.length, 2, "what waited is given after, and no nudge");
  assert.ok(session.prompts[1]!.includes("and then the tests"));
  await r.close();
});

test("a compaction leaves the chat's state as its last turn left it", async () => {
  const r = new Rig();
  const { key, session } = await done(r);
  assert.equal(await r.hub.compact(key), null);
  await settle();
  session.complete();
  await settle();
  assert.equal(r.store.lastTurn(key)!.declared, "final", "the turn before it is still the last");
  assert.equal(r.session(key).running, false);
  assert.equal(session.prompts.length, 1);
  await r.close();
});

test("a compaction that fails is said with why; one asked while a turn runs is refused", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const session = r.claude.last();
  assert.equal(await r.hub.compact(key), "当前任务运行中，停止后再试");
  await r.accept(reply(m, "9999.2", "<@UBOT> -compact", { addressed: true }));
  await settle();
  assert.equal(r.chat.lastText(), "⚠️ 当前任务运行中，停止后再试");
  assert.equal(session.compactions, 0);
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  session.complete();
  await settle();
  assert.equal(await r.hub.compact(key), null);
  session.end({ kind: "failed", reason: "other", message: "Not enough messages to compact." });
  await settle();
  assert.equal(r.chat.lastText(), "⚠️ 无法压缩上下文：Not enough messages to compact.");
  assert.equal(session.prompts.length, 1, "no nudge after it");
  await r.close();
});

test("a runtime that cannot compact says so", async () => {
  const r = new Rig();
  const { key, session } = await done(r);
  (session as { compact?: unknown }).compact = undefined;
  assert.equal(await r.hub.compact(key), "Claude Code 不支持压缩上下文");
  await r.close();
});

test("-clear ends its process; its next turn starts a new runtime session, told so, and its history reads both", async () => {
  const r = new Rig();
  const { m, key, session } = await done(r);
  await r.accept(reply(m, "9999.2", "<@UBOT> -clear", { addressed: true }));
  await settle();
  assert.ok(session.disposed);
  assert.equal(r.session(key).runtimeSessionId, null);
  assert.equal(r.chat.lastText(), "已清空上下文，下一条消息将开始新的对话");
  assert.deepEqual(r.store.runtimeSessions(key), [session.sessionId]);
  await r.accept(reply(m, "9999.3", "<@UBOT> start over", { addressed: true }));
  await settle();
  const fresh = r.claude.last();
  assert.notEqual(fresh, session);
  assert.equal(fresh.options.resume, undefined);
  assert.ok(fresh.prompts[0]!.startsWith("People cleared your context"), fresh.prompts[0]);
  // Its chat read back, its execution history only when needed.
  assert.ok(fresh.prompts[0]!.includes(`chat_history for C1/${m.threadTs}`), fresh.prompts[0]);
  assert.ok(fresh.prompts[0]!.includes("start over"));
  assert.deepEqual(r.store.runtimeSessions(key), [session.sessionId, fresh.sessionId]);
  // Told once.
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  fresh.complete();
  await settle();
  await r.accept(reply(m, "9999.4", "<@UBOT> again", { addressed: true }));
  await settle();
  assert.ok(!fresh.prompts[1]!.includes("People cleared your context"));
  await r.close();
});

test("cleared to go on afresh, its next runtime session reads back its work and its chats, as on another account", async () => {
  const r = new Rig();
  const { m, key, session } = await done(r);
  assert.equal(await r.hub.clear(key, true), null);
  await settle();
  assert.ok(session.disposed);
  assert.equal(r.session(key).runtimeSessionId, null);
  assert.equal(r.chat.lastText(), "已换新上下文，下一条消息将先读回需要的内容再接着做");
  await r.accept(reply(m, "9999.3", "<@UBOT> go on", { addressed: true }));
  await settle();
  const fresh = r.claude.last();
  assert.notEqual(fresh, session);
  assert.equal(fresh.options.resume, undefined);
  assert.ok(fresh.prompts[0]!.startsWith("This is a new conversation"), fresh.prompts[0]);
  assert.ok(fresh.prompts[0]!.includes(`session_history with chat ${key}`), fresh.prompts[0]);
  assert.ok(fresh.prompts[0]!.includes(`chat_history for C1/${m.threadTs}`), fresh.prompts[0]);
  // A later clear by hand is told as one.
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  fresh.complete();
  await settle();
  assert.equal(await r.hub.clear(key), null);
  await settle();
  await r.accept(reply(m, "9999.4", "<@UBOT> again", { addressed: true }));
  await settle();
  assert.ok(r.claude.last().prompts[0]!.startsWith("People cleared your context"), r.claude.last().prompts[0]);
  await r.close();
});

test("cleared to go on afresh, its usage no longer says the context before nor its cache over: not offered again as its process warms", async () => {
  const r = new Rig();
  const { key } = await done(r);
  r.store.db.prepare("UPDATE runtime_sessions SET at = 0 WHERE session_key = ?").run(key);
  r.store.recordUsage(`/t/${key}`, { session: key, offset: 1, model: "claude-opus-5-5" }, "claude", [[
    { id: "c1", at: Date.now() - 3 * 3_600_000, model: "claude-opus-5-5", subagent: false, fast: false, input: 10, cacheRead: 150_000, cacheWrite: 0, cacheWriteLong: 50_000, output: 1, calls: 1, context: 200_000, window: null },
    { turn: null, person: null, thread: null, profile: null },
  ]]);
  const context = () => {
    const u = usageNow(r.store, key)!;
    return [u.contextTokens, u.lastCallAt === undefined, u.cacheMs];
  };
  assert.deepEqual(context(), [200_000, false, 3_600_000]);
  assert.equal(await r.hub.clear(key, true), null);
  await settle();
  assert.deepEqual(context(), [undefined, true, undefined], "cleared");
  // Its process started ahead of the next message (the chat open): a new conversation, nothing of it said yet.
  await r.hub.warm(key);
  await settle();
  assert.notEqual(r.session(key).runtimeSessionId, null);
  assert.deepEqual(context(), [undefined, true, undefined], "warmed");
  await r.close();
});

test("set to, a message to an agent whose large context's cache is over starts it afresh by itself; one still cached goes on", async () => {
  const r = new Rig();
  const { m, key, session } = await done(r);
  // Its last call wrote an hour's cache of 200K: `at` ago.
  let n = 0;
  const called = (at: number) =>
    r.store.recordUsage(`/t/${key}`, { session: key, offset: ++n, model: "claude-opus-5-5" }, "claude", [[
      { id: `c${n}`, at, model: "claude-opus-5-5", subagent: false, fast: false, input: 10, cacheRead: 150_000, cacheWrite: 0, cacheWriteLong: 50_000, output: 1, calls: 1, context: 200_000, window: null },
      { turn: null, person: null, thread: null, profile: null },
    ]]);
  // Its conversation began before it (a fake clock's calls are not after it by themselves).
  r.store.db.prepare("UPDATE runtime_sessions SET at = 0 WHERE session_key = ?").run(key);
  // Not set: it goes on in the same runtime session.
  called(Date.now() - 3 * 3_600_000);
  await r.accept(reply(m, "9999.2", "<@UBOT> and the docs", { addressed: true }));
  await settle();
  assert.equal(r.claude.last(), session);
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  session.complete();
  await settle();
  r.edit((raw) => (raw.afreshWhenCold = true));
  // Set, its cache over: a new runtime session, told to read back what it needs, and said in its chat.
  await r.accept(reply(m, "9999.3", "<@UBOT> now the release", { addressed: true }));
  await settle();
  const fresh = r.claude.last();
  assert.notEqual(fresh, session);
  assert.ok(session.disposed);
  assert.equal(fresh.options.resume, undefined);
  assert.ok(fresh.prompts[0]!.startsWith("This is a new conversation"), fresh.prompts[0]);
  assert.ok(fresh.prompts[0]!.includes("now the release"));
  assert.ok(r.chat.texts().includes("缓存已过期，已自动换新上下文，先读回需要的内容再接着做"), r.chat.texts().join("\n"));
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  fresh.complete();
  await settle();
  // Its cache kept (its last call just now): it goes on.
  called(Date.now());
  await r.accept(reply(m, "9999.4", "<@UBOT> and the tests", { addressed: true }));
  await settle();
  assert.equal(r.claude.last(), fresh);
  assert.equal(fresh.prompts.length, 2);
  await r.close();
});

test("its chat's choice outweighs the station's: set to, a notice starts it afresh too; set not to, a message goes on", async () => {
  const r = new Rig();
  const { m, key, session } = await done(r);
  // Its last call wrote an hour's cache of 200K, three hours ago.
  const called = (n: number) =>
    r.store.recordUsage(`/t/${key}`, { session: key, offset: n, model: "claude-opus-5-5" }, "claude", [[
      { id: `c${n}`, at: Date.now() - 3 * 3_600_000, model: "claude-opus-5-5", subagent: false, fast: false, input: 10, cacheRead: 150_000, cacheWrite: 0, cacheWriteLong: 50_000, output: 1, calls: 1, context: 200_000, window: null },
      { turn: null, person: null, thread: null, profile: null },
    ]]);
  r.store.db.prepare("UPDATE runtime_sessions SET at = 0 WHERE session_key = ?").run(key);
  called(1);
  // The station not set, its chat set to: a job's notice starts it afresh.
  await configure(r.hub, key, { afresh: true });
  assert.equal(r.session(key).afresh, true);
  assert.equal(session.disposed, false, "its process goes on until it is started");
  r.hub.notify(key, "a job ended");
  await settle();
  const fresh = r.claude.last();
  assert.notEqual(fresh, session);
  assert.ok(session.disposed);
  assert.ok(fresh.prompts[0]!.startsWith("This is a new conversation"), fresh.prompts[0]);
  assert.ok(fresh.prompts[0]!.includes("a job ended"));
  await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
  fresh.complete();
  await settle();
  // The station set to, its chat set not to: a message goes on in the same runtime session.
  r.store.db.prepare("UPDATE runtime_sessions SET at = 0 WHERE session_key = ?").run(key);
  called(2);
  r.edit((raw) => (raw.afreshWhenCold = true));
  await configure(r.hub, key, { afresh: false });
  await r.accept(reply(m, "9999.2", "<@UBOT> and the docs", { addressed: true }));
  await settle();
  assert.equal(r.claude.last(), fresh);
  assert.equal(fresh.prompts.length, 2);
  // Given back to the station: null.
  await configure(r.hub, key, { afresh: null });
  assert.equal(r.session(key).afresh, null);
  await r.close();
});

test("clear is refused while a turn runs", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.equal(await r.hub.clear(key), "当前任务运行中，停止后再试");
  assert.equal(r.claude.last().disposed, false);
  await r.close();
});
