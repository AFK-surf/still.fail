import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { Readers } from "../src/read/pool.ts";
import { SaidBuilder } from "../src/read/said-builder.ts";
import { makeStore } from "../src/read/store.ts";
import { chats } from "../src/read/views.ts";
import { Store } from "../src/store/store.ts";

const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" } as const;
function fixture(lengths: number[]) {
  const dir = mkdtempSync(join(tmpdir(), "sidebar-said-reader-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  const threads = lengths.map((length, i) => {
    const key = `s${i}`;
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
      token: key, createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "EMBER", `chat${i}`, null, null).id;
    store.joinThread(thread, key, "ember");
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message',?,?,?,?)");
    store.db.exec("BEGIN");
    put.run(thread, 1, "agent", key, "first", 1);
    for (let n = 2; n <= length; n++) put.run(thread, n, "person", "me", `t${n}`, n);
    store.db.exec("COMMIT");
    store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    return thread;
  });
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("looking up job chat titles does not prepare the unread boundary", () => {
  const f = fixture([150]);
  try {
    const rows = chats(makeStore(f.store.db, f.dir), viewer, false, null, true);
    assert.ok(rows.some((row) => row.thread === f.threads[0]));
    assert.equal(f.store.db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(f.threads[0])?.said_other_known, 0);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
  } finally { f.close(); }
});

test("a sidebar waits for handover, shares preparation, and leaves short old chats untouched", async () => {
  const f = fixture([150, 140, 10]);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const args = { viewer, sessions: null, threads: null };
    const one = readers.read("sharedChats", args, "en");
    const two = readers.read("sharedChats", args, "en");
    // An unrelated read can use the same reader while the old station is still up.
    await readers.read("sharedChats", { viewer, sessions: [], threads: [] }, "en");
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
    previous.resolve();
    const [first, second] = await Promise.all([one, two]);
    assert.equal(second, first);
    const rows = JSON.parse(first) as any[];
    for (let i = 0; i < f.threads.length; i++)
      assert.equal(rows.find((row) => row.thread === f.threads[i])?.said?.other, 1);
    const states = f.threads.map((thread) => f.store.db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(thread)?.said_other_known);
    assert.deepEqual(states, [1, 1, 0], "the short chat was answered without writing old state");
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("the archive and a sidebar share the old-chat worker after handover", async () => {
  const f = fixture([150]);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const archive = readers.prepareSaid(f.threads);
    const sidebar = readers.read("sharedChats", { viewer, sessions: null, threads: null }, "en");
    await readers.read("sharedChats", { viewer, sessions: [], threads: [] }, "en");
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
    previous.resolve();
    const [, text] = await Promise.all([archive, sidebar]);
    assert.equal(JSON.parse(text).find((row: any) => row.thread === f.threads[0])?.said?.other, 1);
    assert.equal(f.store.db.prepare("SELECT said_other_n FROM thread_state WHERE thread=?").get(f.threads[0])?.said_other_n, 1);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("an abandoned sidebar does not start old-chat work after handover", async () => {
  const f = fixture([150]);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const pending = readers.read("sharedChats", { viewer, sessions: null, threads: null }, "en", { signal: controller.signal });
    await readers.read("sharedChats", { viewer, sessions: [], threads: [] }, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await Promise.resolve();
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
    assert.equal(f.store.db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(f.threads[0])?.said_other_known, 0);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("cancelling one sidebar leaves another waiting for the same chat", async () => {
  const f = fixture([150]);
  const previous = Promise.withResolvers<void>();
  const builder = new SaidBuilder(f.path, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const abandoned = builder.ready(f.threads, controller.signal);
    const kept = builder.ready(f.threads);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    await kept;
    assert.equal(f.store.db.prepare("SELECT said_other_n FROM thread_state WHERE thread=?").get(f.threads[0])?.said_other_n, 1);
  } finally { previous.resolve(); await builder.close(); f.close(); }
});

test("closing the sidebar builder releases readers waiting for handover", async () => {
  const f = fixture([150]);
  const previous = Promise.withResolvers<void>();
  const builder = new SaidBuilder(f.path, { previousGone: previous.promise });
  try {
    const pending = builder.ready(f.threads);
    await builder.close();
    await assert.rejects(pending, /station stopping/);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM said_state_guard").get()?.n, 0);
  } finally { previous.resolve(); await builder.close(); f.close(); }
});

test("a stopped sidebar worker retries the old chat", async () => {
  const f = fixture([150]);
  const file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  const real = new URL("../src/read/said-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new SaidBuilder(f.path, {}, pathToFileURL(file));
  try {
    await builder.ready(f.threads);
    assert.equal(existsSync(marker), true);
    assert.equal(f.store.db.prepare("SELECT said_other_n FROM thread_state WHERE thread=?").get(f.threads[0])?.said_other_n, 1);
  } finally { await builder.close(); f.close(); }
});
