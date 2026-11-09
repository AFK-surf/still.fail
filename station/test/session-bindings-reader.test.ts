import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SessionBindingsBuilder } from "../src/read/session-bindings-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { installSessionBindingsIndex, sessionBindingsReady } from "../src/store/session-bindings-index.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "session-bindings-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_binding_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_binding_rows; DROP TABLE session_binding_replaced; DROP TABLE session_binding_meta");
  store.insertSession({ key: "mine", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
    token: "mine", createdAt: 1, lastActiveAt: 1, ws: "mine" });
  db.exec("INSERT INTO bindings(connect,session_key) VALUES('z-first','mine'),('a-second','mine'),('other','other')");
  installSessionBindingsIndex(db);
  return { dir, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const scoped = { connect: null, archived: false, lang: "en", viewer: { workspace: "mine", home: false } };
const empty = { ...scoped, viewer: { workspace: "empty", home: false } };

test("session reads release the reader and share binding preparation after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    let answered = false;
    const abandoned = readers.read("summary", { key: "mine" }, "en", { signal: controller.signal });
    const kept = readers.read("sessions", scoped, "en").then((text) => { answered = true; return text; });
    assert.deepEqual(JSON.parse(await readers.read("sessions", empty, "en")), []);
    assert.equal(answered, false);
    assert.equal(sessionBindingsReady(f.store.db), false);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const rows = JSON.parse(await kept);
    assert.deepEqual(rows.map((row: any) => row.key), ["mine"]);
    assert.deepEqual(rows[0].boundTo, ["z-first", "a-second"]);
    assert.equal(sessionBindingsReady(f.store.db), true);
  } finally { controller.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("an abandoned session read does not prepare bindings after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const pending = readers.read("summary", { key: "mine" }, "en", { signal: controller.signal });
    await readers.read("sessions", empty, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await readers.read("sessions", empty, "en");
    const meta = f.store.db.prepare("SELECT complete, last_rowid FROM session_binding_meta WHERE id=1").get()!;
    assert.equal(meta.complete, 0);
    assert.equal(meta.last_rowid, null);
  } finally { controller.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("archive preparation and a session read share old binding work", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const abandoned = readers.prepareSessionBindings(controller.signal);
    const kept = readers.read("summary", { key: "mine" }, "en");
    assert.deepEqual(JSON.parse(await readers.read("sessions", empty, "en")), []);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept).boundTo, ["z-first", "a-second"]);
    assert.equal(sessionBindingsReady(f.store.db), true);
  } finally { controller.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("a session reader reports an incompatible binding index", async () => {
  const f = fixture(), readers = new Readers(f.dir, 1);
  try {
    f.store.db.exec("UPDATE session_binding_meta SET version=2");
    await assert.rejects(readers.read("summary", { key: "mine" }, "en"), /session binding.*version/i);
  } finally { readers.close(); f.close(); }
});

test("a stopped binding worker retries its pending index", async () => {
  const f = fixture(), file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  try {
    const real = new URL("../src/read/session-bindings-worker.ts", import.meta.url).href;
    writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
    const builder = new SessionBindingsBuilder(join(f.dir, "stillfail.db"), {}, pathToFileURL(file));
    try {
      await builder.readyIndex();
      assert.ok(existsSync(marker));
      assert.equal(sessionBindingsReady(f.store.db), true);
      assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM session_binding_rows").get()!.n, 3);
    } finally { await builder.close(); }
  } finally { f.close(); }
});
