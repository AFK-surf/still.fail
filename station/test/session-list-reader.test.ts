import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { installSessionListIndex } from "../src/store/session-list-index.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "session-list-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_list_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_list_rows; DROP TABLE session_list_replaced; DROP TABLE session_list_meta");
  for (const [key, ws] of [["mine", "mine"], ["other", "other"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: key, createdAt: 1, lastActiveAt: 1, ws });
  installSessionListIndex(db);
  return { dir, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const scoped = { connect: null, archived: false, lang: "en", viewer: { workspace: "mine", home: false } };
const global = { ...scoped, viewer: null };

test("session lists release the reader while sharing preparation after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    let answered = false;
    const abandoned = readers.read("sessions", scoped, "en", { signal: controller.signal });
    const kept = readers.read("sessions", scoped, "en").then((text) => { answered = true; return text; });
    const all = JSON.parse(await readers.read("sessions", global, "en"));
    assert.equal(all.length, 2);
    assert.equal(answered, false);
    assert.equal(f.store.db.prepare("SELECT complete FROM session_list_meta WHERE id=1").get()!.complete, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).map((row: any) => row.key), ["mine"]);
    assert.equal(f.store.db.prepare("SELECT complete FROM session_list_meta WHERE id=1").get()!.complete, 1);
  } finally { controller.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("an abandoned session list does not start indexing after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const pending = readers.read("sessions", scoped, "en", { signal: controller.signal });
    await readers.read("sessions", global, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await readers.read("sessions", global, "en");
    const meta = f.store.db.prepare("SELECT complete, last_rowid FROM session_list_meta WHERE id=1").get()!;
    assert.equal(meta.complete, 0);
    assert.equal(meta.last_rowid, null);
  } finally { controller.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("a reader reports an incompatible session list index instead of retrying", async () => {
  const f = fixture(), readers = new Readers(f.dir, 1);
  try {
    f.store.db.exec("UPDATE session_list_meta SET version=2");
    await assert.rejects(readers.read("sessions", scoped, "en"), /session list.*version/i);
  } finally { readers.close(); f.close(); }
});
