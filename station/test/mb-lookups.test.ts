// The MoonBit builders of a large old store's per-chat lookups (station/mb, src/lookups) prepare them as
// `closedCardsStep` and `peopleSinceStep` do: the same schema, and for the same chats, batch by batch, the same answers
// and the same tables, with the station writing meanwhile; a small store gets the same native index.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { closedCardsStep } from "../src/store/legacy-closed-cards.ts";
import { peopleSinceStep } from "../src/store/legacy-people-since.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

type Kind = { role: string; step: typeof closedCardsStep; prefix: string; native: string };
const kinds: Kind[] = [
  { role: "closed-cards", step: closedCardsStep, prefix: "legacy_closed", native: "closed_cards_thread_at" },
  { role: "people-since", step: peopleSinceStep, prefix: "legacy_people_time", native: "entries_people_since" },
];

/// A store from before the lookups: three chats of 150 messages (people's and agents'), their cards closed, the native
/// indexes gone; `small`: one chat of a few.
function old(small = false) {
  const dir = mkdtempSync(join(tmpdir(), "mb-lookups-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  db.exec("BEGIN");
  const threads = ["a", "b", "c"].slice(0, small ? 1 : 3).map((key) => store.openThread("ember", "CHAT", key, null, null).id);
  const entry = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts) VALUES(?,?,'message',?,'x','t',?,?)");
  const close = db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,?,?,?)");
  for (const thread of threads) for (let n = 1; n <= (small ? 5 : 150); n++) {
    entry.run(thread, n, n % 3 === 0 ? "person" : "agent", n * 7 % 50, n % 4 === 0 ? `ts-${thread}-${n}` : null);
    close.run(thread, n, `p${n % 2}`, n * 11 % 40);
  }
  db.exec("COMMIT");
  db.exec("DROP INDEX closed_cards_thread_at; DROP INDEX entries_people_since");
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

/// What the station writes while a chat is being prepared, the same on both.
function writes(f: ReturnType<typeof old>, round: number) {
  const db = f.store.db, [a, b] = f.threads as [number, number];
  if (round === 1) {
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,151,'message','person','x','late',99)").run(a);
    db.prepare("UPDATE entries SET at = 3 WHERE thread = ? AND n = 3").run(a);
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,151,'p9',77)").run(a);
    db.prepare("UPDATE closed_cards SET at = 1 WHERE thread = ? AND n = 2").run(a);
  }
  if (round === 2) {
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 6").run(a);
    db.prepare("DELETE FROM closed_cards WHERE thread = ? AND n = 5").run(a);
    db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,9,'message','agent','x','replaced',5)").run(b);
  }
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store, k: Kind): string {
  const db = store.db;
  const schema = (db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE ? OR name = ? ORDER BY type, name").all(`${k.prefix}%`, k.native) as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE ? ORDER BY name").all(`${k.prefix}%`) as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => db.prepare(`SELECT * FROM ${name} ORDER BY 1, 2`).all())]);
}

for (const k of kinds) for (const small of [false, true]) {
  test(`the MoonBit builder prepares ${k.role} as the TypeScript does${small ? " (a small store: the native index)" : ""}`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(small), mb = old(small);
    const builder = new MbProcess(binary!, ["--builder", k.role, "--db", mb.path]);
    try {
      let steps = 0;
      for (const [i, thread] of ts.threads.entries()) {
        for (let round = 0; round < 20; round++) {
          if (i === 0) { writes(ts, round); writes(mb, round); }
          const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
          builder.postMessage({ thread });
          const ours = await answered;
          assert.equal(ours.error, undefined);
          assert.equal(ours.done, k.step(ts.store.db, thread).done, `chat ${thread} round ${round}`);
          assert.equal(tables(mb.store, k), tables(ts.store, k), `chat ${thread} round ${round}`);
          steps++;
          if (ours.done) break;
        }
      }
      assert.ok(small ? steps === 1 : steps >= 9, `${steps} steps`);
      // a deleted chat asked again does not get its scope back
      for (const f of [ts, mb]) f.store.db.prepare("DELETE FROM threads WHERE id = ?").run(f.threads[0]);
      const answered = new Promise<{ done: boolean }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ thread: 9999 });
      assert.equal((await answered).done, k.step(ts.store.db, 9999).done);
      assert.equal(tables(mb.store, k), tables(ts.store, k));
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}

test("a closed-card lookup from before its cleanup trigger gets it, as the TypeScript gives it", async () => {
  assert.notEqual(binary, null);
  const k = kinds[0]!, ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", k.role, "--db", mb.path]);
  try {
    for (const f of [ts, mb]) { closedCardsStep(f.store.db, f.threads[0]!); f.store.db.exec("DROP TRIGGER legacy_closed_drop_thread"); }
    const answered = new Promise<{ done: boolean }>((resolve) => builder.once("message", resolve));
    builder.postMessage({ thread: mb.threads[1] });
    assert.equal((await answered).done, closedCardsStep(ts.store.db, ts.threads[1]!).done);
    assert.equal(tables(mb.store, k), tables(ts.store, k));
    assert.notEqual(mb.store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'legacy_closed_drop_thread'").get(), undefined);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});
