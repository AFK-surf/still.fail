// The MoonBit builder of a program's chat order (station/mb, src/outflow) makes the index as
// `installOutflowChatIndex` does and settles it as `outflowChatIndexStep` does: the same schema, and the same chats,
// batch by batch, give the same answers and the same order, before and after the station writes.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { OutflowChatIndex } from "../src/read/chat-index-builder.ts";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { installOutflowChatIndex, outflowChatIndexReady, outflowChatIndexStep } from "../src/store/outflow-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database of 300 chats in sessions of two workspaces and none, some shared, with messages, no index yet.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-outflow-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", undefined]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws } as Parameters<Store["insertSession"]>[0]);
  const threads: number[] = [];
  store.db.exec("BEGIN");
  for (let i = 0; i < 300; i++) {
    const owner = ["a", "b", "h"][i % 3]!;
    const thread = store.openThreadOf("ember", "CHAT", `chat-${i}`, `chat ${i}`, "ann@x", owner);
    store.joinThread(thread.id, owner, "ember");
    if (i % 10 === 0) store.joinThread(thread.id, "b", "ember");
    store.db.prepare("UPDATE threads SET created_at=? WHERE id=?").run(i, thread.id);
    if (i % 4 !== 0) store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','ann@x','body',?)").run(thread.id, 1000 + i);
    threads.push(thread.id);
  }
  store.db.exec("COMMIT");
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const spaced = (sql: string | null) => (sql ?? "").replace(/\s+/g, " ").replace(/\( /g, "(").replace(/ \)/g, ")").trim();
function schema(store: Store): string {
  return JSON.stringify((store.db.prepare("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name LIKE 'outflow%' ORDER BY name").all() as { sql: string | null }[])
    .map((row) => ({ ...row, sql: spaced(row.sql) })));
}
function order(store: Store): string {
  return JSON.stringify([
    store.db.prepare("SELECT thread, scope, at, dirty FROM outflow_chat_order ORDER BY thread, scope").all(),
    store.db.prepare("SELECT cursor, last, done FROM outflow_chat_progress").all(),
  ]);
}

test("the MoonBit builder makes and settles the chat order as the TypeScript does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "outflow-chats", "--db", mb.path]);
  const ask = async (scope: string) => {
    const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
    builder.postMessage({ scope });
    const ours = await answered;
    assert.equal(ours.error, undefined);
    installOutflowChatIndex(ts.store.db);
    return { mb: ours.done, ts: outflowChatIndexStep(ts.store.db, scope).done };
  };
  try {
    const steps: { mb: boolean; ts: boolean }[] = [];
    for (let i = 0; i < 20; i++) { const s = await ask("WA"); steps.push(s); if (s.mb) break; }
    assert.ok(steps.length >= 5, JSON.stringify(steps));
    assert.equal(schema(mb.store), schema(ts.store), "the same tables, index and triggers");
    assert.equal(order(mb.store), order(ts.store));
    // the station writes: a new message, a chat gone, a session moved; then every scope is settled again
    for (const f of [ts, mb]) {
      f.store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,2,'message','person','ann@x','new',5000)").run(f.threads[3]);
      f.store.db.prepare("DELETE FROM threads WHERE id = ?").run(f.threads[6]);
      f.store.db.prepare("UPDATE sessions SET ws = 'C' WHERE key = 'b'").run();
    }
    for (const scope of ["WA", "WB", "WC", "H"]) {
      for (let i = 0; i < 10; i++) { const s = await ask(scope); steps.push(s); if (s.mb) break; }
    }
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(order(mb.store), order(ts.store));
    assert.equal(outflowChatIndexReady(mb.store.db, { workspace: "A", home: true }), true);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's chat order index is made and settled by the MoonBit builder", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const index = new OutflowChatIndex(f.path, {}, undefined, binary);
  try {
    await index.ready({ workspace: "B", home: true });
    assert.equal(outflowChatIndexReady(f.store.db, { workspace: "B", home: true }), true);
  } finally {
    await index.close();
    f.close();
  }
});
