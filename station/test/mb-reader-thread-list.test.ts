// Every thread as chat_list has it (`threadList`) by the MoonBit reader (station/mb src/readops/threads.mbt;
// read/pool.ts MOVED) as the worker reads it, on the same database: still.fail's chats and a platform's, of sessions
// and of none, edited, with letters in their own log and among messages, a read mark of no one's, chats said in at
// the same moment and never; with and without the edits' index.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads every thread as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-thread-list-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  for (const key of ["s1", "s2"]) store.insertSession({ key, connect: key === "s2" ? "team" : "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1 } as Parameters<Store["insertSession"]>[0]);
  const say = (t: number, ts: string, author: string, text: string, at: number, extra: Record<string, unknown> = {}) =>
    store.insertMessage({ ...newMessage(t, ts, "person", author, text), at, ...extra } as ReturnType<typeof newMessage>);
  const own = store.openThread("ember", "CHAT", "own", null, null).id;
  store.joinThread(own, "s1", "ember");
  say(own, "1", "p@x", "first thing", 100);
  store.editMessage("ember", "CHAT", "own", "1", "first thing, edited");
  say(own, "2", "q@x", "same moment", 500);
  say(own, "3", "p@x", "a letter among them", 400, { letter: { way: "out", title: "To Y", link: null } });
  store.insertLetter({ thread: own, ts: "L1", authorKind: "person", author: "r@x", text: "kept apart", letter: { way: "in", title: "From Z", link: null } });
  const slack = store.openThread("slack:T", "C1", "171.1", "Named", null).id;
  store.joinThread(slack, "s2", "team");
  say(slack, "171.2", "U1", "from slack", 500);
  say(slack, "171.3", "U2", "again", 300);
  const lonely = store.openThread("ember", "CHAT", "lonely", null, null).id;
  say(lonely, "9", "p@x", "nobody's", 200);
  // Two never said in: the older id made later comes first.
  const silent = store.openThread("ember", "CHAT", "silent", "Silent", null).id;
  const quiet = store.openThread("slack:T", "C2", "172.1", null, null).id;
  store.db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(50, silent);
  store.db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(10, quiet);
  store.db.prepare("INSERT INTO reads(viewer, thread, n, at) VALUES ('', ?, 1, 1)").run(own);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers) => readers.read("threadList", {}, "zh").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  try {
    const first = await read(program);
    assert.deepEqual(first, await read(worker));
    const said = JSON.stringify(first);
    for (const sign of ["first thing, edited", "\"slack:team:U1\"", "\"lettersLast\":1", "\"read\":1", "\"title\":\"Silent\""]) assert.ok(said.includes(sign), sign);
    store.db.exec("DROP INDEX IF EXISTS entries_edits");
    assert.deepEqual(await read(program), await read(worker));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
