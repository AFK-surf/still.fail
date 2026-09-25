import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { Hub, isStopCommand, runtimeOverride, sessionKey } from "../src/hub.ts";
import { Store } from "../src/store.ts";
import { FakeChat, FakeDriver, message, settle } from "./fakes.ts";

function setup(overrides: { maxNudges?: number; maxWarmClaude?: number; warmMinutes?: number } = {}) {
  const dataDir = mkdtempSync(join(tmpdir(), "ember-test-"));
  const config = parseConfig({
    profiles: [
      { id: "cc", runtime: "claude", home: "homes/cc" },
      { id: "cx", runtime: "codex", home: "homes/cx" },
    ],
    ...overrides,
  }, dataDir);
  const store = new Store(":memory:");
  const chat = new FakeChat();
  const claude = new FakeDriver("claude");
  const codex = new FakeDriver("codex");
  const hub = new Hub({ config, store, chat, drivers: { claude, codex }, mcpUrl: "http://127.0.0.1:1/mcp" });
  const tools = Object.fromEntries(hub.tools().map((t) => [t.name, t]));
  const call = (key: string, name: string, args: Record<string, unknown>) => tools[name]!.run(key, args);
  return { config, store, chat, claude, codex, hub, call };
}

test("a mention starts a session and prompts the runtime with the message", async () => {
  const { hub, claude, store } = setup();
  const m = message({ text: "<@UBOT> fix the build" });
  await hub.accept(m);
  await settle();
  const session = claude.last;
  assert.equal(session.prompts.length, 1);
  assert.match(session.prompts[0]!, /<slack user="U1" ts="[\d.]+">\n<@UBOT> fix the build\n<\/slack>/);
  assert.equal(store.getSession(sessionKey("C1", m.threadTs))?.runtimeSessionId, session.id);
  assert.equal(session.options.cwd.endsWith("workspace"), true);
});

test("thread chatter without a session is ignored", async () => {
  const { hub, claude } = setup();
  await hub.accept(message({ addressed: false, text: "just talking" }));
  await settle();
  assert.equal(claude.sessions.length, 0);
});

test("a mention inside an existing thread tells the agent about earlier messages", async () => {
  const { hub, claude } = setup();
  await hub.accept(message({ threadTs: "1.000001", ts: "5.000001" }));
  await settle();
  assert.match(claude.last.prompts[0]!, /already had messages/);
});

test("a message during a running turn is steered into it", async () => {
  const { hub, claude } = setup();
  const first = message();
  await hub.accept(first);
  await settle();
  await hub.accept(message({ threadTs: first.threadTs, ts: "9999.1", addressed: false, text: "also check tests" }));
  await settle();
  assert.equal(claude.last.prompts.length, 1);
  assert.match(claude.last.steers[0]!, /also check tests/);
});

test("the same message delivered twice is handled once", async () => {
  const { hub, claude } = setup();
  const m = message();
  await hub.accept(m);
  await hub.accept({ ...m });
  await settle();
  assert.equal(claude.last.prompts.length, 1);
});

test("a turn ending without final/block is nudged, then reported after maxNudges", async () => {
  const { hub, claude, chat } = setup({ maxNudges: 1 });
  await hub.accept(message());
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
  const { hub, claude, chat, call } = setup();
  const m = message();
  await hub.accept(m);
  await settle();
  const key = sessionKey("C1", m.threadTs);
  assert.equal(await call(key, "chat_post", { text: "**done**", kind: "final" }), "Posted, and recorded state final.");
  claude.last.end();
  await settle();
  assert.equal(claude.last.prompts.length, 1);
  assert.deepEqual(chat.posts, [{ thread: { channel: "C1", threadTs: m.threadTs }, text: "**done**" }]);
});

test("chat_state rejects kinds other than final and block", async () => {
  const { hub, call } = setup();
  const m = message();
  await hub.accept(m);
  await assert.rejects(call(sessionKey("C1", m.threadTs), "chat_state", { kind: "wait" }), /final" or "block/);
});

test("-stop aborts the running turn and confirms once it ends", async () => {
  const { hub, claude, chat } = setup();
  const m = message();
  await hub.accept(m);
  await settle();
  await hub.accept(message({ threadTs: m.threadTs, ts: "9999.2", text: "<@UBOT> -stop" }));
  await settle();
  assert.equal(claude.last.aborts, 1);
  assert.equal(claude.last.steers.length, 0, "-stop is not forwarded to the agent");
  claude.last.end({ kind: "aborted" });
  await settle();
  assert.equal(chat.posts.at(-1)!.text, "已停止当前任务。");
  assert.equal(claude.last.prompts.length, 1, "no nudge after a stop");
});

test("a failed turn is reported to the thread and not nudged", async () => {
  const { hub, claude, chat } = setup();
  await hub.accept(message());
  await settle();
  claude.last.end({ kind: "failed", reason: "auth", message: "401 Missing API key" });
  await settle();
  assert.match(chat.posts.at(-1)!.text, /认证失败.*401 Missing API key/);
  assert.equal(claude.last.prompts.length, 1);
});

test("messages that arrive while a turn cannot take them go in the next turn", async () => {
  const { hub, claude } = setup();
  const m = message();
  await hub.accept(m);
  await settle();
  const session = claude.last;
  session.steer = async () => false; // e.g. a codex turn that is not steerable
  await hub.accept(message({ threadTs: m.threadTs, ts: "9999.3", addressed: false, text: "one more thing" }));
  await settle();
  session.end();
  await settle();
  assert.equal(session.prompts.length, 2);
  assert.match(session.prompts[1]!, /one more thing/);
});

test("[codex] picks the codex runtime for a new session", async () => {
  const { hub, claude, codex, store } = setup();
  const m = message({ text: "<@UBOT> [codex] refactor this" });
  await hub.accept(m);
  await settle();
  assert.equal(claude.sessions.length, 0);
  assert.equal(codex.sessions.length, 1);
  assert.equal(store.getSession(sessionKey("C1", m.threadTs))?.profile, "cx");
});

test("after a restart a cut-off turn is resumed", async () => {
  const first = setup();
  const m = message();
  await first.hub.accept(m);
  await settle();
  const runtimeId = first.claude.last.id;

  // Same store, new hub and drivers: what a restart looks like.
  const claude = new FakeDriver("claude");
  const hub = new Hub({ config: first.config, store: first.store, chat: first.chat, drivers: { claude, codex: new FakeDriver("codex") }, mcpUrl: "x" });
  await hub.recover();
  await settle();
  assert.equal(claude.last.options.resume, runtimeId);
  assert.match(claude.last.prompts[0]!, /restarted while you were in the middle of a turn/);
});

test("when the runtime session cannot be resumed, a new one starts and is told to catch up", async () => {
  const { hub, claude } = setup();
  const m = message();
  await hub.accept(m);
  await settle();
  const old = claude.last;
  old.end({ kind: "failed", reason: "exited", message: "gone" });
  old.events.closed("gone");
  await settle();
  claude.unresumable.add(old.id);
  await hub.accept(message({ threadTs: m.threadTs, ts: "9999.4", addressed: false, text: "still there?" }));
  await settle();
  assert.notEqual(claude.last, old);
  assert.equal(claude.last.options.resume, undefined);
  assert.match(claude.last.prompts[0]!, /could not be restored[\s\S]*still there\?/);
});

test("idle claude processes beyond the warm limit are evicted, oldest first", async () => {
  const { hub, claude } = setup({ maxWarmClaude: 1, warmMinutes: 0 });
  const a = message({ ts: "1.1", threadTs: "1.1" });
  const b = message({ ts: "2.1", threadTs: "2.1" });
  await hub.accept(a);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  await hub.accept(b);
  await settle();
  claude.last.end({ kind: "aborted" });
  await settle();
  hub.evictIdle(Date.now() + 1000);
  await settle();
  assert.deepEqual(claude.sessions.map((s) => s.disposed), [true, false]);
});

test("a running turn is never evicted", async () => {
  const { hub, claude } = setup({ maxWarmClaude: 0, warmMinutes: 0 });
  await hub.accept(message());
  await settle();
  hub.evictIdle(Date.now() + 10_000_000);
  await settle();
  assert.equal(claude.last.disposed, false);
});

test("command parsing", () => {
  assert.equal(runtimeOverride("<@UBOT> [Codex] go"), "codex");
  assert.equal(runtimeOverride("[claude] go"), "claude");
  assert.equal(runtimeOverride("go [codex]"), undefined);
  assert.equal(isStopCommand("<@UBOT>  -stop "), true);
  assert.equal(isStopCommand("please -stop now"), false);
});
