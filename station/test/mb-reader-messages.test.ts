// Messages read merged with their latest edit by the MoonBit reader (station/mb src/readops/messages.mbt; read/pool.ts
// MOVED) as the worker reads them: a session's undelivered messages and letters (`pendingDeliveries`), the question a
// need names (`stateQuestion`), a chat's card still waiting with its post (`reviewPendingCard`); on messages edited,
// with files and quotes (right and wrong), letters in and out, agents' identities, cards answered and not.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads merged messages as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-messages-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
  let ts = 0;
  const say = (thread: number, kind: "person" | "agent", text: string, extra: Record<string, unknown> = {}) => {
    const t = String(++ts);
    store.insertMessage({ ...newMessage(thread, t, kind, kind === "agent" ? "s" : "a@x", text), at: ts * 10, ...extra } as ReturnType<typeof newMessage>);
    return { t, n: (store.db.prepare("SELECT n FROM entries WHERE thread = ? AND ts = ?").get(thread, t) as { n: number }).n };
  };
  const chat = (name: string) => {
    const id = store.openThread("ember", "CHAT", name, name, null).id;
    store.joinThread(id, "s", "ember");
    return id;
  };
  const a = chat("a"), b = chat("b"), c = chat("c"), d = chat("d");
  const open1 = say(d, "agent", "pick one", { card: { type: "options", options: [{ label: "y" }] } });
  const asked = say(a, "agent", "which one?", { card: { type: "options", options: [{ label: "x" }] }, agentIdentity: { model: "opus", runtime: "claude" } });
  const plain = say(a, "agent", "  question without a card  ");
  const p1 = say(a, "person", "hello", { attachments: [{ name: "f.png", path: "/f.png", size: 3, width: 10, height: 5 }], quotes: [{ author: "s", text: "which", comment: "this", ts: asked.t }] });
  store.editMessage("ember", "CHAT", "a", p1.t, "hello, edited");
  const p2 = say(b, "person", "second chat");
  store.db.prepare("UPDATE entries SET quotes = ? WHERE thread = ? AND n = ?").run(JSON.stringify([{ author: 1 }]), b, p2.n);
  const blank = say(b, "agent", "   ");
  const other = say(c, "agent", "not this session's", { card: { type: "text" } });
  store.db.prepare("UPDATE entries SET author = 'other' WHERE thread = ? AND n = ?").run(c, other.n);
  for (const [thread, n] of [[a, p1.n], [b, p2.n]]) store.db.prepare("INSERT OR IGNORE INTO deliveries (thread, n, session) VALUES (?, ?, 's')").run(thread, n);
  const letter = store.insertLetter({ thread: a, ts: String(++ts), authorKind: "person", author: "x@y", text: "a letter", letter: { way: "in", title: "From X", link: null } });
  store.db.prepare("INSERT OR IGNORE INTO letter_deliveries (thread, n, session) VALUES (?, ?, 's')").run(a, letter);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [await read(readers, "pendingDeliveries", { key: "s" }), await read(readers, "pendingDeliveries", { key: "nobody" })];
    for (const thread of [a, b, c, d, 9999]) out.push(await read(readers, "reviewPendingCard", { thread }));
    for (const t of [asked.t, plain.t, p1.t, blank.t, other.t, open1.t, "nope"]) out.push(await read(readers, "stateQuestion", { key: "s", threads: [a, b, c, d], ts: t }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["hello, edited", "a letter", "\"apart\":true", "\"found\"", "\"invalid\"", "\"missing\"", "f.png"]) assert.ok(said.includes(sign), sign);
    // A person writing after them: the card and the plain question answered.
    say(a, "person", "the answer");
    say(d, "person", "y");
    assert.deepEqual(await all(program), await all(worker));
    // Without the edits' index (a store whose lookup must be repaired): read bounded, or refused alike.
    store.db.exec("DROP INDEX IF EXISTS entries_edits");
    const bounded = await all(program);
    assert.deepEqual(bounded, await all(worker));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
