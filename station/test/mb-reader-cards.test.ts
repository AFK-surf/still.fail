// A chat's pending card read by the MoonBit reader (station/mb src/readops; read/pool.ts MOVED) as the worker reads it:
// `historyPendingCard`, `statePendingCard`, `deliveryCardState` on chats with a card waiting, one answered by a person,
// one closed, one only of options (from before cards), one card that is not JSON, none at all, before and after their
// card posts are indexed (a read refused meanwhile has them prepared and asks again).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads a chat's pending card as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-cards-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let ts = 0;
  const say = (thread: number, kind: "person" | "agent", text: string, extra: Record<string, unknown> = {}) =>
    store.insertMessage({ ...newMessage(thread, String(++ts), kind, kind === "agent" ? "s" : "a@x", text), at: ts * 10, ...extra } as ReturnType<typeof newMessage>)[0];
  const chat = (name: string) => store.openThread("ember", "CHAT", name, name, null).id;
  const waiting = chat("waiting"), answered = chat("answered"), closed = chat("closed"), legacy = chat("legacy"), broken = chat("broken"), plain = chat("plain");
  const card = { type: "options", options: [{ label: "yes" }, { label: "no" }] };
  say(waiting, "person", "ask me");
  say(waiting, "agent", "first", { card });
  say(waiting, "person", "answer one");
  say(waiting, "agent", "second", { card: { type: "text", placeholder: "x", "2": 1, dup: 1 } });
  say(answered, "agent", "pick", { card });
  say(answered, "person", "picked");
  const shut = say(closed, "agent", "pick", { card });
  store.db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, 'a@x', 1)").run(closed, typeof shut === "object" ? (shut as { n: number }).n : 1);
  say(legacy, "agent", "old pick");
  store.db.prepare("UPDATE entries SET options = ? WHERE thread = ? AND kind = 'message'").run(JSON.stringify(["a", "b"]), legacy);
  say(broken, "agent", "bad card");
  store.db.prepare("UPDATE entries SET card = 'not json' WHERE thread = ? AND kind = 'message'").run(broken);
  say(plain, "person", "hello");
  say(plain, "agent", "hi");
  const threads = [waiting, answered, closed, legacy, broken, plain, 9999];
  const ns = (store.db.prepare("SELECT thread, n FROM entries WHERE kind = 'message' ORDER BY thread, n").all() as { thread: number; n: number }[]);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const thread of threads) out.push(await read(readers, "historyPendingCard", { thread }));
    out.push(await read(readers, "statePendingCard", { threads }), await read(readers, "statePendingCard", { threads: [plain] }));
    for (const { thread, n } of [...ns, { thread: waiting, n: 999 }]) out.push(await read(readers, "deliveryCardState", { thread, n }));
    return out;
  };
  try {
    // The program first: its refusals have the posts indexed before the worker reads them.
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    assert.deepEqual(await all(program), first);
    assert.ok(JSON.stringify(first).includes("\"ended\""), JSON.stringify(first));
    assert.ok(first.some((v) => typeof v === "number"));
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
