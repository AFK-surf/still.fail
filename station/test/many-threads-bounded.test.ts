// A chat that joins a thread for each thing it posts (a release posted to a Slack channel each time: slack_api starts
// a thread and the chat takes part in it) comes to take part in thousands. What a turn, its tools, the auto-archive,
// the archive review's choice of threads and what its agent is told read of them stays the same however many it joined:
// they look at its recent threads (store `recentSessionThreads`), never every one.
import assert from "node:assert/strict";
import { StatementSync } from "node:sqlite";
import { test } from "node:test";
import { OLDER_THREADS, toldCleared, toldLongChat, toldResumeLost } from "../src/sessions/afresh.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { undecided } from "../src/sessions/review.ts";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { newMessage } from "../src/store/rows.ts";
import { archiveFactsOf, RECENT_THREADS, Store } from "../src/store/store.ts";
import { Rig, message } from "./hub-fakes.ts";

/// Rows the main thread's statements gave back, and how many statements ran, while `counting`.
const counted = { rows: 0, calls: 0, on: false };
const proto = StatementSync.prototype as unknown as Record<string, (...args: unknown[]) => unknown>;
const originals = new Map<string, (...args: unknown[]) => unknown>();
for (const name of ["all", "get", "iterate", "run"]) {
  const original = proto[name]!;
  originals.set(name, original);
  proto[name] = function (this: unknown, ...args: unknown[]) {
    const out = original.apply(this, args);
    if (counted.on) {
      counted.calls++;
      counted.rows += name === "all" ? (out as unknown[]).length : name === "get" && out !== undefined ? 1 : 0;
    }
    return out;
  };
}

type Measure = { rows: number; calls: number; text: number };
async function measure(f: () => unknown): Promise<Measure> {
  counted.rows = 0; counted.calls = 0; counted.on = true;
  let text = 0;
  try {
    const out = await f();
    if (typeof out === "string") text = out.length;
  } finally { counted.on = false; }
  return { rows: counted.rows, calls: counted.calls, text };
}

/// What each step reads with a chat in `n` threads besides its own.
async function scenario(n: number): Promise<Record<string, Measure>> {
  const r = new Rig();
  try {
    const m = message();
    await r.accept(m);
    await r.quiet();
    const key = sessionKey("cl", "C1", m.threadTs);
    await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "hi", kind: "all_done", done: "answered hi" });
    r.claude.last().complete();
    await r.quiet();
    // The releases it posted, each a thread of its own.
    const tsOf = (i: number) => `3000.${String(i).padStart(6, "0")}`;
    for (let i = 0; i < n; i++) {
      const t = r.store.openThread("slack:T1", "C2", tsOf(i), null, key);
      r.store.joinThread(t.id, key, "cl");
      r.store.insertMessage(newMessage(t.id, t.threadTs, "agent", key, `release ${i}`));
    }
    const out: Record<string, Measure> = {};
    r.chat.answers.set("chat.postMessage", { ok: true, ts: "9100.1" });
    out.release = await measure(() => r.call(key, "slack_api", { method: "chat.postMessage", params: { channel: "C2", text: "next release" } }));
    // Someone asks about the latest release there: a turn, its answer and its end.
    out.turn = await measure(async () => {
      await r.accept({ channel: "C2", threadTs: "9100.1", ts: "9100.2", user: "U1", text: "<@UBOT> what changed?", addressed: true });
      await r.quiet();
      await r.call(key, "chat_post", { to: "C2/9100.1", text: "notes", kind: "all_done", done: "answered", about: "9100.2" });
      r.claude.last().complete();
      await r.quiet();
    });
    out.state = await measure(() => r.call(key, "chat_state", { kind: "all_done", done: "answered what changed", about: "9100.2" }));
    out.need = await measure(() => r.call(key, "chat_post", { to: "C2/9100.1", text: "ship it?", kind: "need_human", need: "decide" }));
    out.refused = await measure(() => r.refused(key, "chat_post", { to: "C9/1.1", text: "x" }));
    out.cleared = await measure(() => toldCleared(r.hub, key));
    out.resumeLost = await measure(() => toldResumeLost(r.hub, key));
    out.longChat = await measure(() => toldLongChat(r.hub, key) ?? "");
    out.undecided = await measure(() => undecided(r.hub));
    out.facts = await measure(() => { assert.ok(archiveFactsOf(r.store.db, [key])[key]!.threads.length <= RECENT_THREADS); });
    // Kept by someone: the auto-archive looks at its threads and leaves it (archiving tells each of them it changed).
    r.store.keepChat("someone@example.com", r.thread("C2", "9100.1").id);
    out.autoArchive = await measure(() => autoArchive(r.hub, Number.MAX_SAFE_INTEGER / 2));
    assert.equal(r.store.getSession(key)?.archivedAt, null);
    for (const told of [out.cleared, out.refused]) assert.ok(told.text > 0);
    assert.ok(toldCleared(r.hub, key).includes(OLDER_THREADS));
    assert.ok(toldCleared(r.hub, key).includes("C2/9100.1"), "the thread it just posted in is among those it is told of");
    return out;
  } finally { await r.close(); }
}

test("with ten times the threads, nothing a chat's turn, tools, archive or prompts read grows", async () => {
  const few = await scenario(RECENT_THREADS * 3);
  const many = await scenario(RECENT_THREADS * 30);
  for (const [step, small] of Object.entries(few)) {
    const large = many[step]!;
    assert.ok(large.rows <= small.rows && large.calls <= small.calls, `${step}: ${JSON.stringify(small)} with few threads, ${JSON.stringify(large)} with many`);
    assert.equal(large.text, small.text, `${step}: what the agent is told is as long`);
  }
});

test("a session's recent threads: its own chat, the newest it joined and the ones it heard from last, all where few", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const home = store.openThread("ember", "CHAT", "home", null, null);
    db.prepare("UPDATE threads SET home='s' WHERE id=?").run(home.id);
    store.joinThread(home.id, "s", "ember");
    const ids: number[] = [];
    const add = (count: number) => {
      for (let i = 0; i < count; i++) {
        const t = store.openThread("slack:T1", "C", `t-${ids.length}`, null, null);
        store.joinThread(t.id, "s", "slack");
        ids.push(t.id);
      }
    };
    add(5);
    // Few: every one, in sessionThreads' order.
    assert.deepEqual(store.recentSessionThreads("s"), { threads: store.sessionThreads("s"), more: false });
    add(100);
    // Someone wrote in an old one.
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(ids[3]);
    while (!prepareLatestThreadStep(db, "s").done) { /* bounded batches */ }
    const { threads, more } = store.recentSessionThreads("s");
    const got = threads.map((t) => t.thread.id);
    assert.equal(more, true);
    assert.equal(got.length, RECENT_THREADS);
    assert.equal(got[0], home.id, "its own chat first");
    assert.equal(got[1], ids[3], "then the one it heard from last");
    assert.ok(got.includes(ids.at(-1)!), "and the newest it joined");
    assert.equal(new Set(got).size, got.length);
    // However many there are, a few statements and at most twice the limit's rows.
    counted.rows = 0; counted.calls = 0; counted.on = true;
    store.recentSessionThreads("s");
    counted.on = false;
    assert.ok(counted.calls <= 4 && counted.rows <= 2 * RECENT_THREADS + 3, JSON.stringify(counted));
  } finally { store.close(); }
});

test.after(() => { for (const [name, original] of originals) proto[name] = original; });
