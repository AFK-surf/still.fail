// What the chats' people hear about (admin/notify.rs): a turn told by how it ended, a person's message to the others,
// the station's ⚠️ to everyone; gathered and handed on once.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { Notifier } from "../src/cloud/notify.ts";
import { Cloud } from "../src/cloud/state.ts";
import { ops } from "../src/read/ops.ts";
import { blockedAsk, openStore } from "../src/read/store.ts";
import { turnNotice, wentWrong } from "../src/read/notices.ts";
import { Store, newMessage } from "../src/store/store.ts";

const turn = (declared: string | null, outcome: string, need?: string) => ({ kind: "message", outcome, declared, need, startedAt: 100, endedAt: 200 });
const said = (authorKind: any, author: string, createdAt: number) =>
  ({ agentIdentity: null, thread: 1, n: 3, ts: "1.1", authorKind, author, text: "修好了", attachments: [], quotes: [], declared: null, client: null, createdAt, editedAt: null }) as any;

test("a turn is told by how it ended", () => {
  const mine = said("agent", "k", 150);
  assert.deepEqual(turnNotice(turn("final", "completed"), mine, "k", "file", true), ["done", "修好了"]);
  assert.deepEqual(turnNotice(turn("block", "completed"), mine, "k", "file", true), ["block", "修好了"]);
  assert.deepEqual(turnNotice(turn("block", "completed", "要 Stripe 的测试 key"), mine, "k", "file", true), ["block", "要 Stripe 的测试 key"]);
  const old = said("agent", "k", 50);
  assert.equal(turnNotice(turn("final", "completed"), old, "k", "file", true), null);
  assert.equal(turnNotice(turn(null, "failed"), old, "k", "file", true), null);
  assert.equal(wentWrong("⚠️ 无法启动 agent：没有 claude"), "无法启动 agent：没有 claude");
  assert.equal(wentWrong("已停止当前任务"), null);
  assert.equal(turnNotice(turn("final", "completed"), said("person", "a@b.c", 150), "k", "file", true), null);
  assert.equal(turnNotice(turn(null, "completed"), mine, "k", "file", true), null);
  assert.equal(turnNotice(turn("waiting", "completed"), mine, "k", "file", true), null);
  // Blocked on what its people were already told of, or on nothing waiting for them: told as a turn that ended done.
  assert.deepEqual(turnNotice(turn("block", "completed", "要 Stripe 的测试 key"), mine, "k", "file", false), ["done", "修好了"]);
  assert.equal(turnNotice(turn("block", "completed", "要 Stripe 的测试 key"), old, "k", "file", false), null);
});

test("a blocked turn's ask is told once, while it waits", () => {
  const dir = mkdtempSync(join(tmpdir(), "notify-"));
  // A clock moving on a millisecond a step: each of the turns and messages below after the one before.
  let now = 1000;
  const store = Store.open(join(dir, "stillfail.db"), join(dir, "archive"), { currentTimeMillisUnsafe: () => now++ } as never);
  const reader = openStore(dir);
  store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" } as any);
  const chat = store.openThread("ember", "EMBER", "1.1", null, "ada@x.com");
  store.joinThread(chat.id, "k", "ember");
  const kinds = (id: string) => {
    const turn = reader.db.prepare("SELECT * FROM turns WHERE id = ?").get(id) as any;
    const t = { declared: turn.declared, need: turn.need, startedAt: turn.started_at, endedAt: turn.ended_at, ...(turn.about_n === null ? {} : { about: { thread: turn.about_thread, seq: turn.about_n } }) };
    return blockedAsk(reader, chat.id, "k", t as any);
  };
  // It asks, and the turn ends blocked on that: new.
  store.startTurn("t1", "k", "input");
  store.insertMessage(newMessage(chat.id, "1.2", "agent", "k", "要不要改 Surge？"));
  store.endTurn("t1", "completed", null, "block", null);
  assert.equal(kinds("t1")?.fresh, true);
  // Woken by a job, it says how things go and ends blocked on the same ask: told already.
  store.startTurn("t2", "k", "notice");
  store.endTurn("t2", "completed", null, "waiting", 60);
  store.startTurn("t3", "k", "notice");
  store.insertMessage(newMessage(chat.id, "1.3", "agent", "k", "CI 过了"));
  store.endTurn("t3", "completed", null, "block", null);
  assert.equal(kinds("t3")?.fresh, false);
  // Once a person has written, nothing waits for them, until it asks again.
  store.insertMessage(newMessage(chat.id, "1.4", "person", "ada@x.com", "先做别的"));
  store.startTurn("t4", "k", "input");
  store.endTurn("t4", "completed", null, "block", null);
  assert.equal(kinds("t4"), null);
  store.startTurn("t5", "k", "input");
  store.insertMessage(newMessage(chat.id, "1.5", "agent", "k", "那 Surge 呢？"));
  store.endTurn("t5", "completed", null, "block", null);
  assert.equal(kinds("t5")?.fresh, true);
});

test("a chat's people hear of its turns and of each other, once, gathered", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "notify-"));
  const store = Store.open(join(dir, "stillfail.db"), join(dir, "archive"));
  const reader = openStore(dir);
  // What the notifier asks of the readers, followed: the notices it gathers are all made once none is left.
  let asking = 0;
  const readers: any = {
    read: async (op: string, a: any) => {
      asking++;
      try {
        return JSON.stringify(ops[op]!(reader, a));
      } finally {
        asking--;
      }
    },
  };
  // In its home workspace "ws", and in "w2" it joined (docs/multi-workspace.md).
  const cloud: any = Object.assign(Object.create(Cloud.prototype), {
    state: { origin: "http://x", station: "s", workspace: "ws", workspace_name: "ws", name: "s", peers: [], revocations: [], joined: [{ workspace: "w2", workspace_name: "W2", name: "s", peers: [], revocations: [] }] },
    lock: null,
  });
  // Its gathering second, on a clock of the test's.
  const scope = Effect.runSync(Scope.make());
  t.after(() => Effect.runPromise(Scope.close(scope, Exit.void)));
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  const notifier = new Notifier(store, readers, cloud, null as any, { clock });
  const posted: any[][] = [];
  const workspaces: (string | undefined)[] = [];
  notifier.post = async (n, ws) => void (posted.push(n), workspaces.push(ws));
  store.insertSession({ key: "k", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t", createdAt: 1, lastActiveAt: 1, createdBy: "ada@x.com" } as any);
  const chat = store.openThread("ember", "EMBER", "1.1", null, "ada@x.com");
  store.joinThread(chat.id, "k", "ember");
  store.insertMessage(newMessage(chat.id, "1.2", "person", "bob@x.com", "看一下"));
  store.startTurn("t1", "k", "input");
  store.insertMessage({ ...newMessage(chat.id, "1.3", "agent", "k", "好了"), declared: "final" });
  store.endTurn("t1", "completed", null, "final", null);
  store.insertMessage(newMessage(chat.id, "1.4", "ember", "ember", "⚠️ 没能启动"));
  const settle = () => new Promise((r) => setImmediate(r));
  for (let i = 0; i < 5 || asking > 0; i++) await settle();
  assert.equal(posted.length, 0, "nothing before the second is up");
  // The second goes by (again, should its wait have begun only after the clock moved).
  for (let i = 0; i < 100 && posted.length === 0; i++) {
    await Effect.runPromise(clock.adjust("1 second"));
    for (let j = 0; j < 5; j++) await settle();
  }
  // Each about its message (what a notification opens the chat at).
  const all = posted.flat().map((n) => [n.kind, n.to.join(","), n.text, n.seq]);
  assert.equal(posted.length, 1, "gathered into one post");
  assert.deepEqual(all.sort(), [
    ["done", "ada@x.com,bob@x.com", "好了", 2],
    ["failed", "ada@x.com,bob@x.com", "没能启动", 3],
    ["message", "ada@x.com", "看一下", 1],
  ]);
  // The home workspace's: posted as before, without naming it.
  assert.deepEqual(workspaces, [undefined]);

  // A chat of the joined workspace: its own post, naming it; one of a workspace the station is not in: none.
  store.insertSession({ key: "j", connect: "ember", runtime: "claude", profile: "cc", workspace: "/j", token: "tj", createdAt: 1, lastActiveAt: 1, createdBy: "cy@x.com", ws: "w2" } as any);
  const theirs = store.openThread("ember", "EMBER", "2.1", null, "cy@x.com");
  store.joinThread(theirs.id, "j", "ember");
  store.insertSession({ key: "g", connect: "ember", runtime: "claude", profile: "cc", workspace: "/g", token: "tg", createdAt: 1, lastActiveAt: 1, createdBy: "dee@x.com", ws: "gone" } as any);
  const gone = store.openThread("ember", "EMBER", "3.1", null, "dee@x.com");
  store.joinThread(gone.id, "g", "ember");
  store.insertMessage(newMessage(theirs.id, "2.2", "person", "eve@x.com", "在吗"));
  store.insertMessage(newMessage(gone.id, "3.2", "person", "fay@x.com", "在吗"));
  for (let i = 0; i < 5 || asking > 0; i++) await settle();
  for (let i = 0; i < 100 && posted.length === 1; i++) {
    await Effect.runPromise(clock.adjust("1 second"));
    for (let j = 0; j < 5; j++) await settle();
  }
  assert.deepEqual(workspaces, [undefined, "w2"]);
  assert.deepEqual(posted[1]!.map((n) => [n.session, n.text]), [["j", "在吗"]]);
  notifier.close();
});
