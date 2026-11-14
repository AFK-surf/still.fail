// The copies' reads are bounded (replica/export.ts; station/AGENTS.md, Its data): every statement the export makes of
// stillfail.db searches by an index, the rowid or a key; a pass after something changed reads a few rows, however
// many the station has; and the main thread's writes run no statement more for the copies than they did before them.
import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { Fibers } from "../src/ops/fibers.ts";
import { Copies } from "../src/replica/copies.ts";
import { Exporter, READS, SMALL, byKey, marksOf, nothingTold, pageOf } from "../src/replica/export.ts";
import { TABLES } from "../src/replica/format.ts";
import { InlineRunner } from "../src/replica/runner.ts";
import { Store } from "../src/store/store.ts";
import { takeQueries } from "../src/store/timed.ts";
import { HOME, ORIGIN, chat, dataDir } from "./replica-fakes.ts";

const THREAD_MARKS = ["reads", "hidden_chats", "muted_chats", "kept_chats", "dismissed"];

test("every read the export makes searches by an index, the rowid or a key", () => {
  const store = Store.open(":memory:");
  const all: [string, string][] = Object.entries(READS);
  for (const t of SMALL) all.push([`page of ${t}`, pageOf(t)]);
  for (const t of THREAD_MARKS) all.push([`${t} of a thread`, marksOf(t, "thread")]);
  all.push(["pins of a session", marksOf("pins", "session")]);
  for (const t of [...THREAD_MARKS, "pins"]) all.push([`${t} by key`, byKey(t, TABLES[t]!)]);
  for (const [name, sql] of all) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all() as { detail: string }[]).map((r) => r.detail);
    // A table scanned whole: never. (The viewers of a marks table are walked one by one: its first one by its index,
    // LIMIT 1; the walk's own rows are the few viewers.)
    const scans = plan.filter((d) => /^SCAN /.test(d) && !/^SCAN (CONSTANT ROW|v)$/.test(d) && !(/ USING COVERING INDEX sqlite_autoindex_/.test(d) && sql.includes("ORDER BY viewer LIMIT 1")));
    assert.deepEqual(scans, [], `${name}: ${plan.join("; ")}`);
    assert.ok(plan.some((d) => d.startsWith("SEARCH ")), `${name} searches: ${plan.join("; ")}`);
  }
  store.close();
});

test("a pass after a message reads a few rows, however many chats the station has", () => {
  const data = dataDir();
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const threads: number[] = [];
  for (let i = 0; i < 200; i++) threads.push(chat(store, data, `chat:${i}`, null, 20));
  const e = new Exporter({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: ORIGIN, now: () => 1 });
  e.setPlaces({ home: HOME, workspaces: [{ workspace: HOME, name: "x" }] });
  let p = e.pass(nothingTold());
  while (p.more) p = e.pass(nothingTold());
  // a message, and its chat's session said to have changed (a turn)
  store.insertMessage({ thread: threads[7]!, ts: "new", authorKind: "person", author: "p@x", text: "hello" });
  const told = nothingTold();
  told.sessions.push("chat:7");
  told.threads.push(threads[7]!);
  const after = e.pass(told);
  assert.equal(after.wrote, 1);
  assert.ok(after.read <= 12, `a pass read ${after.read} rows for one message and one session`);
  // as the exporter starts again: the small tables whole, a page at a time, never a chat's messages
  e.close();
  const again = new Exporter({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: ORIGIN, now: () => 1 });
  again.setPlaces({ home: HOME, workspaces: [{ workspace: HOME, name: "x" }] });
  const small = SMALL.reduce((n, t) => n + (store.db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get() as { n: number }).n, 0);
  const first = again.pass(nothingTold());
  assert.equal(first.wrote, 0, "nothing changed while it was away");
  assert.ok(first.read <= small * 2 + 10, `${first.read} rows read as it started, of ${small} in the small tables`);
  again.close();
  store.close();
});

test("the main thread's writes run no statement more for the copies than before them", async () => {
  const scope = Effect.runSync(Scope.make());
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  const write = (store: Store, data: string, tag: string) => {
    const thread = chat(store, data, `chat:${tag}`, null, 10);
    store.setRead("p@x", thread, 3);
    store.setPin("p@x", `chat:${tag}`, true);
    store.setThreadTitle(thread, "Named");
    store.startTurnFor(`turn-${tag}`, `chat:${tag}`, "message", { profile: "cc", person: "p@x", thread });
    store.endTurn(`turn-${tag}`, "completed", null, "all_done", null);
  };
  const count = (copies: boolean) => {
    const data = dataDir();
    const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
    const fibers = new Fibers("copies", clock);
    const runner = new InlineRunner({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: ORIGIN, now: () => 1 });
    const c = new Copies({ data, here: () => ORIGIN, places: () => ({ home: HOME, workspaces: [{ workspace: HOME, name: "x" }] }), roster: () => [], ask: async () => null, runner, fibers, changed: () => {}, restart: async () => null });
    if (copies) store.subscribe((change) => c.told(change));
    takeQueries();
    write(store, data, "one");
    const calls = takeQueries().calls;
    return { calls, close: async () => { await c.close(); await runner.close(); await fibers.close(); store.close(); } };
  };
  const without = count(false);
  const withCopies = count(true);
  assert.ok(without.calls > 0);
  assert.equal(withCopies.calls, without.calls, "the same statements on the main thread with the copies kept as without");
  await without.close();
  await withCopies.close();
  await Effect.runPromise(Scope.close(scope, Exit.void));
});
