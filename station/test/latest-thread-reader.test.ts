import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { followLatestThreadRequests } from "../src/read/latest-thread-requests.ts";
import { Readers } from "../src/read/pool.ts";
import { latestThreadReady } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";

test("a store read requests its latest order once and uses it after handover", async () => {
  const dir = mkdtempSync(join(process.cwd(), ".latest-thread-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const prepare = readers.prepareLatestThreads.bind(readers), calls: string[][] = [];
  let prepared: Promise<void> | undefined;
  readers.prepareLatestThreads = (sessions, signal) => {
    calls.push([...sessions]);
    return (prepared = prepare(sessions, signal));
  };
  const stop = followLatestThreadRequests(store, readers);
  try {
    store.insertSession({ key: "s", connect: "slack", runtime: "claude", profile: "cc", workspace: "/w/s",
      token: "s", createdAt: 1, lastActiveAt: 1 });
    const first = store.openThread("slack", "C", "first", null, null);
    const second = store.openThread("slack", "C", "second", null, null);
    store.joinThread(first.id, "s", "slack"); store.joinThread(second.id, "s", "slack");
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(first.id);
    assert.equal(store.latestThread("s")?.thread.id, first.id);
    assert.equal(store.latestThread("s")?.thread.id, first.id);
    assert.deepEqual(calls, [["s"]]);
    assert.equal(latestThreadReady(db, "s"), false);
    previous.resolve();
    assert.ok(prepared);
    await prepared;
    assert.equal(latestThreadReady(db, "s"), true);
    db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',NULL)").run(second.id);
    assert.equal(store.latestThread("s")?.thread.id, second.id);
    assert.deepEqual(calls, [["s"]]);
  } finally {
    stop(); previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("closing a follower does not remove a newer request handler", () => {
  const store: { requestLatestThread: ((session: string) => void) | null } = { requestLatestThread: null };
  const stop = followLatestThreadRequests(store, { prepareLatestThreads: async () => {} });
  const newer = () => {};
  store.requestLatestThread = newer;
  stop();
  assert.equal(store.requestLatestThread, newer);
});
