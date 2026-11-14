// chat_list searched (`searchChatList`) by the MoonBit reader (station/mb src/readops/search_chats.mbt; read/pool.ts
// MOVED) as the worker searches it, on the same database: matches by a chat's title, its automatic one, its first
// words, its latest words as edited, a session's key or title, letters of other cases; the station's, the home
// workspace's and another's; limits of none, one and more; with and without the edits' index.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader searches chat_list as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-search-chats-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  for (const [key, ws, title] of [["alpha-1", "home", "Deploy Bot"], ["beta-2", null, null], ["gamma-3", "w", "Ünïcode İstanbul"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, title, ws } as Parameters<Store["insertSession"]>[0]);
  let ts = 0;
  const say = (t: number, author: string, text: string) => {
    const at = String(++ts);
    store.insertMessage({ ...newMessage(t, at, "person", author, text), at: 1000 + ts * 10 } as ReturnType<typeof newMessage>);
    return at;
  };
  const specs: [string, string | null, string[], string[]][] = [
    ["a", "Release Notes", ["alpha-1"], ["write the CHANGELOG", "done"]],
    ["b", null, ["beta-2"], ["Find the Flaky test", "it was the clock"]],
    ["c", null, ["gamma-3"], ["σίγμα ΣΊΓΜΑ", "ΤΈΛΟΣ"]],
    ["d", "Empty", [], []],
    ["e", null, ["alpha-1", "beta-2"], ["shared chat about deploys"]],
    ["f", null, ["ghost"], ["a session not there"]],
  ];
  for (const [key, title, members, said] of specs) {
    const t = store.openThread("ember", "CHAT", key, title, null).id;
    for (const m of members) store.joinThread(t, m, "ember");
    let first: string | null = null;
    for (const text of said) first ??= say(t, "p@x", text);
    if (key === "b" && first !== null) store.editMessage("ember", "CHAT", "b", first, "Find the flaky TEST, edited");
    if (key === "d") store.db.prepare("UPDATE threads SET auto_title = 'Quarterly Report' WHERE id = ?").run(t);
  }
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const query of ["release", "changelog", "flaky test", "edited", "clock", "σίγμα", "τέλος", "quarterly", "alpha-1", "deploy", "i̇stanbul", "ghost", "", "nothing like it"])
      for (const [ws, home, limit] of [[null, null, 50], ["home", "home", 50], ["w", "home", 1], [null, null, 0]] as const)
        out.push(await read(readers, "searchChatList", { ws, home, limit, query }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"title\":\"Release Notes\"", "edited", "\"autoTitle\":\"Quarterly Report\"", "\"key\":\"gamma-3\"", "\"session\":\"ghost\""]) assert.ok(said.includes(sign), sign);
    store.db.exec("DROP INDEX IF EXISTS entries_edits");
    const bounded = await all(program);
    assert.deepEqual(bounded, await all(worker));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
