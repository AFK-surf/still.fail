// The first page of chat_list (`recentChatList`) by the MoonBit reader (station/mb src/readops/recent.mbt, src/recent
// page.mbt; read/pool.ts MOVED) as the worker reads it, on the same database: the station's page, the home
// workspace's (its default part and its own joined), another workspace's; chats named and not, edited, of several
// sessions, of none, in both of home's parts; limits of none, a few and more than there are; with and without the edits'
// index.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads the first page of chat_list as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-recent-chats-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  for (const [key, ws] of [["h1", "home"], ["h2", null], ["w1", "w"], ["w2", "w"], ["gone", "w"]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, title: key === "w1" ? "Session one" : null, ws } as Parameters<Store["insertSession"]>[0]);
  store.db.prepare("UPDATE sessions SET archived_at = 5 WHERE key = 'gone'").run();
  let ts = 0;
  const say = (t: number, key: string, author: string, text: string) => {
    const at = String(++ts);
    store.insertMessage({ ...newMessage(t, at, "person", author, text), at: 1000 + ts * 10 } as ReturnType<typeof newMessage>);
    return at;
  };
  const chats: number[] = [];
  for (let i = 0; i < 14; i++) {
    const key = `c${i}`;
    const t = store.openThread("ember", "CHAT", key, i % 3 === 0 ? null : `Chat ${i}`, null).id;
    chats.push(t);
    // Chat 12 is both in the home workspace's own part and its default one (their overlap).
    const members = i === 12 ? ["h1", "h2"] : i % 4 === 0 ? ["h1"] : i % 4 === 1 ? ["h2", "w1"] : i % 4 === 2 ? ["w1", "w2", "gone"] : [];
    if (i === 6) store.db.prepare("UPDATE threads SET auto_title = 'Auto named' WHERE id = ?").run(t);
    for (const m of members) store.joinThread(t, m, "ember");
    if (i % 5 !== 4) {
      const first = say(t, key, "p@x", `${"first words ".repeat(i === 3 ? 40 : 1)}${i}`);
      if (i % 2 === 0) store.editMessage("ember", "CHAT", key, first, `first words ${i}, edited`);
      say(t, key, "q@x", `later ${i}`);
    }
  }
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const [ws, home] of [[null, null], ["home", "home"], ["w", "home"], ["nobody", "home"]] as const)
      for (const limit of [0, 3, 50]) out.push(await read(readers, "recentChatList", { ws, home, limit }));
    out.push(await read(readers, "recentChatList", { ws: null, home: null, limit: -1 }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    // Without the edits' index (a store whose lookup must be repaired): messages read bounded, or refused alike.
    store.db.exec("DROP INDEX IF EXISTS entries_edits");
    assert.deepEqual(await all(program), await all(worker));
    for (const sign of ["edited", "\"title\":\"Session one\"", "\"firstText\":\"first words", "\"lastMessage\":null", "\"total\":14", "\"session\":\"gone\""])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
