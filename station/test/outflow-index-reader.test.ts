import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { Store } from "../src/store/store.ts";
import { Readers } from "../src/read/pool.ts";
import { OutflowChatIndex } from "../src/read/chat-index-builder.ts";
import { installOutflowChatIndex, outflowChatIndexStep } from "../src/store/outflow-index.ts";
import { openStore } from "../src/read/store.ts";
import { outflowChats } from "../src/read/outflow.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "outflow-reader-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1, ws: "A" });
  const thread = store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
  store.joinThread(thread.id, "a", "ember");
  store.db.prepare("UPDATE threads SET created_at=10 WHERE id=?").run(thread.id);
  const say = (n: number, at: number) => store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','ann@x','body',?)").run(thread.id, n, at);
  say(1, 20);
  return { dir, path, store, thread, say, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("a reader builds chat ordering on demand, then settles new messages before answering", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name='outflow_chat_progress'").get(), undefined);
    const pending = readers.read("outflowChats", { since: 0, ws: { workspace: "A", home: false }, limit: 1 }, "en");
    // An unrelated read can use the reader while the requested index waits for the previous station.
    assert.ok(JSON.parse(await readers.read("resourceChats", { sessions: ["a"] }, "en")));
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name='outflow_chat_progress'").get(), undefined);
    previous.resolve();
    const first = JSON.parse(await pending);
    assert.deepEqual(first.chats.map((chat: any) => [chat.thread, chat.lastActiveAt]), [[f.thread.id, 20]]);
    f.say(2, 70);
    const second = JSON.parse(await readers.read("outflowChats", { since: 0, ws: { workspace: "A", home: false }, limit: 1 }, "en"));
    assert.deepEqual(second.chats.map((chat: any) => [chat.thread, chat.lastActiveAt]), [[f.thread.id, 70]]);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("an abandoned chat export does not start an old-chat build after handover", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const pending = readers.read("outflowChats", { since: 0, ws: { workspace: "A", home: false }, limit: 1 }, "en", { signal: controller.signal });
    await readers.read("resourceChats", { sessions: ["a"] }, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await Promise.resolve();
    assert.equal(f.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name='outflow_chat_progress'").get(), undefined);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("a stopped chat order worker resumes its pending request", async () => {
  const f = fixture();
  const file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  const real = new URL("../src/read/chat-index-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new OutflowChatIndex(f.path, {}, pathToFileURL(file));
  try {
    await builder.ready({ workspace: "A", home: false });
    assert.equal(existsSync(marker), true);
    assert.deepEqual(Object.values(f.store.db.prepare("SELECT scope,thread,at FROM outflow_chat_order").get()!), ["WA", f.thread.id, 20]);
  } finally { await builder.close(); f.close(); }
});

test("nearby chat exports reuse their index worker", async () => {
  const f = fixture();
  const file = join(f.dir, "worker.mjs"), starts = join(f.dir, "starts");
  const real = new URL("../src/read/chat-index-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { appendFileSync } from 'node:fs';\nappendFileSync(${JSON.stringify(starts)}, 'x');\nawait import(${JSON.stringify(real)});\n`);
  const builder = new OutflowChatIndex(f.path, {}, pathToFileURL(file));
  try {
    await builder.ready({ workspace: "A", home: false });
    f.say(2, 70);
    await builder.ready({ workspace: "A", home: false });
    assert.equal(readFileSync(starts, "utf8"), "x");
  } finally { await builder.close(); f.close(); }
});

test("the exported page and its readiness check see the same snapshot", () => {
  const f = fixture();
  installOutflowChatIndex(f.store.db);
  while (!outflowChatIndexStep(f.store.db, "WA").done) { /* bounded batches */ }
  const reader = openStore(f.dir), viewer = { workspace: "A", home: false };
  try {
    reader.db.exec("BEGIN");
    // The first read pins the snapshot before a concurrent message makes the maintained order dirty.
    const first = outflowChats(reader, 0, viewer, { limit: 1, before: null }) as any;
    f.say(2, 70);
    const same = outflowChats(reader, 0, viewer, { limit: 1, before: null }) as any;
    assert.equal(first.chats[0].lastActiveAt, 20);
    assert.deepEqual(same, first);
    reader.db.exec("COMMIT");
    assert.throws(() => outflowChats(reader, 0, viewer, { limit: 1, before: null }), /order is still being prepared/);
    while (!outflowChatIndexStep(f.store.db, "WA").done) { /* bounded batches */ }
    assert.equal((outflowChats(reader, 0, viewer, { limit: 1, before: null }) as any).chats[0].lastActiveAt, 70);
  } finally { reader.db.close(); f.close(); }
});
