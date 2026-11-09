import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { historyRuntimeSources, makeStore, openStore, runtimeSessionSources } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("history source pages preserve the old order and current source through concurrent changes", () => {
  const data = mkdtempSync(join(tmpdir(), "history-source-snapshot-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let read: ReturnType<typeof openStore> | undefined;
  try {
    writer.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    writer.db.exec("BEGIN");
    const put = writer.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    for (let i = 0; i < 320; i++) put.run("one", `id-${i}`, i % 2 ? "cc" : null, i % 3, i % 2 ? "claude" : null);
    writer.db.exec("COMMIT");
    writer.setRuntimeSessionId("one", "id-200");
    read = openStore(data);
    const expected = runtimeSessionSources(read, "one");
    const first = historyRuntimeSources(read, "one");
    writer.db.prepare("DELETE FROM runtime_sessions WHERE session_key='one' AND id='id-2'").run();
    writer.setRuntimeSessionId("one", "id-300");
    const second = historyRuntimeSources(read, "one");
    assert.deepEqual([...first].filter((source) => source !== null), expected);
    assert.deepEqual([...second].filter((source) => source !== null), runtimeSessionSources(read, "one"));
    first.close(); second.close();
    assert.equal((read.db.prepare("SELECT COUNT(*) AS n FROM sqlite_temp_master WHERE name LIKE 'history_runtime_snapshot_%'").get() as { n: number }).n, 0);

    read.db.exec("BEGIN");
    const inTransaction = historyRuntimeSources(read, "one");
    inTransaction.close();
    read.db.exec("ROLLBACK");
    read.db.exec("PRAGMA query_only=ON");
    const fallback = historyRuntimeSources(read, "one");
    assert.deepEqual([...fallback].filter((source) => source !== null), runtimeSessionSources(read, "one"));
    fallback.close();
  } finally { read?.db.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("unusual runtime source ids keep the identity behavior of the original reader", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.db.exec("BEGIN");
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one',CAST(? AS TEXT),'cc',?,'claude')");
    for (let i = 0; i < 140; i++) put.run(Buffer.from(`part\0${i}`), i);
    store.db.exec("COMMIT");
    store.setRuntimeSessionId("one", "part");
    const read = makeStore(store.db, "/no-station-config");
    const expected = runtimeSessionSources(read, "one");
    const snapshot = historyRuntimeSources(read, "one");
    try { assert.deepEqual([...snapshot].filter((source) => source !== null), expected); }
    finally { snapshot.close(); }
  } finally { store.close(); }
});
