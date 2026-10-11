// What is said on a station as one log (store/schema.ts `addEntryPlace`, read/views.ts `said`): each entry its place,
// never given twice, read from any place on whatever thread it was said in; and a database from before places.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { openStore } from "../src/read/store.ts";
import { said } from "../src/read/views.ts";
import { MANUAL, Store, newMessage } from "../src/store/store.ts";

const dirs: string[] = [];
const closing: { close(): void }[] = [];
after(() => {
  for (const c of closing) {
    try {
      c.close();
    } catch {}
  }
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

const viewer = { sub: "a@x", email: "a@x", name: "a", role: "member", workspace: "w", device: "d" } as any;

/// A station's store on disk with two chats, and how a reader answers GET /said of it.
function station() {
  const data = mkdtempSync(join(tmpdir(), "said-test-"));
  dirs.push(data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  closing.push(store);
  for (const key of ["a", "b"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
  const one = store.openThread("ember", "EMBER", "1.0", null, null);
  const two = store.openThread("ember", "EMBER", "2.0", null, null);
  store.joinThread(one.id, "a", "ember");
  store.joinThread(two.id, "b", "ember");
  let ts = 0;
  const say = (thread: number, text: string, by: "person" | "agent" = "person") => store.insertMessage(newMessage(thread, `9.${++ts}`, by, by === "agent" ? "a" : "a@x", text));
  const reader = openStore(data);
  closing.push(reader.db);
  const read = (after: number, limit?: number) => said(reader, viewer, { after: String(after), ...(limit === undefined ? {} : { limit: String(limit) }) }) as { at: number; entries: any[] };
  return { store, one: one.id, two: two.id, say, read };
}

test("what is said has its place on the station, whatever thread it is said in", () => {
  const { store, one, two, say, read } = station();
  assert.deepEqual(read(0), { at: 0, entries: [] });
  say(one, "一");
  say(two, "二");
  say(one, "三", "agent");
  assert.equal(store.saidAt(), 3);
  const all = read(0);
  assert.equal(all.at, 3);
  // In the order it was said, each as GET /threads/:id/entries has it, with its place.
  assert.deepEqual(all.entries.map((e) => [e.pos, e.thread, e.n, e.text]), [[1, one, 1, "一"], [2, two, 1, "二"], [3, one, 2, "三"]]);
  assert.equal(all.entries[2].authorKind, "agent");
  assert.ok("authorName" in all.entries[0]);
  assert.deepEqual(store.entriesAfter(one, 0).map((e) => e.pos), [1, 3]);
  // From a place on: what came after it; from the last: nothing, and how far it goes.
  assert.deepEqual(read(1).entries.map((e) => e.pos), [2, 3]);
  assert.deepEqual(read(3), { at: 3, entries: [] });
  // A page at a time: one that got as many as it asked asks again from the last it got.
  assert.deepEqual(read(0, 2).entries.map((e) => e.pos), [1, 2]);
  assert.deepEqual(read(2, 2).entries.map((e) => e.pos), [3]);
});

test("a place is never given twice: a thread archived takes its entries along, and they are the same once back", () => {
  const { store, one, two, say, read } = station();
  say(one, "一");
  say(two, "二");
  say(two, "三");
  // The thread said in last goes to its archive file: its rows leave the database, the highest places with them.
  store.setArchived("b", true, MANUAL);
  assert.equal((store.db.prepare("SELECT COUNT(*) AS c FROM entries WHERE thread = ?").get(two) as any).c, 0);
  assert.equal(store.saidAt(), 3);
  assert.deepEqual(read(0).entries.map((e) => e.pos), [1], "what is in an archive is read by its thread, not from a place");
  // What is said next is after all that was: no place of the archived thread's is given again.
  say(one, "四");
  assert.deepEqual(read(1).entries.map((e) => [e.pos, e.thread]), [[4, one]]);
  // Someone writes in the archived thread: it comes back as it was, its entries at their places, the new one after.
  say(two, "五");
  assert.deepEqual(store.entriesAfter(two, 0).map((e) => [e.n, e.pos]), [[1, 2], [2, 3], [3, 5]]);
  assert.deepEqual(read(0).entries.map((e) => e.pos), [1, 2, 3, 4, 5]);
  assert.equal(read(0).at, 5);
});

test("a database from before places: its entries take the order they were written in, and what is said goes on from them", () => {
  const data = mkdtempSync(join(tmpdir(), "said-test-"));
  dirs.push(data);
  const path = join(data, "stillfail.db");
  const first = Store.open(path, join(data, "archive"));
  first.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
  const thread = first.openThread("ember", "EMBER", "1.0", null, null);
  first.joinThread(thread.id, "a", "ember");
  for (const [ts, text] of [["9.1", "一"], ["9.2", "二"]] as const) first.insertMessage(newMessage(thread.id, ts, "person", "a@x", text));
  first.close();
  // As a station from before left it: no places, no count of them.
  const old = new DatabaseSync(path);
  old.exec("DROP INDEX entries_pos; ALTER TABLE entries DROP COLUMN pos; DROP TABLE counters;");
  old.close();
  // A reader of such a database (the station not opened it yet) answers that nothing has a place.
  const before = openStore(data);
  assert.deepEqual(said(before, viewer, { after: "0" }), { at: 0, entries: [] });
  before.db.close();
  const store = Store.open(path, join(data, "archive"));
  closing.push(store);
  assert.deepEqual(store.entriesAfter(thread.id, 0).map((e) => [e.n, e.pos]), [[1, 1], [2, 2]]);
  assert.equal(store.saidAt(), 2);
  store.insertMessage(newMessage(thread.id, "9.3", "person", "a@x", "三"));
  assert.deepEqual(store.entriesAfter(thread.id, 0).map((e) => e.pos), [1, 2, 3]);
  // Opened again: nothing is counted anew.
  store.close();
  const again = Store.open(path, join(data, "archive"));
  closing.push(again);
  assert.equal(again.saidAt(), 3);
});
