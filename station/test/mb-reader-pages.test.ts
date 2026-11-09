// Pages of a chat's messages read by the MoonBit reader (station/mb src/readops/pages.mbt; read/pool.ts MOVED) as the
// worker reads them: `latestMessages`, `chatHistoryMessages` and `openedChatSaid`, on a long chat of messages, edits,
// letter messages and entries that are not messages, every kind of limit, before a message, before one not there.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader reads pages of messages as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-pages-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const thread = store.openThread("ember", "CHAT", "long", "Long", null).id;
  const short = store.openThread("ember", "CHAT", "short", "Short", null).id;
  let ts = 0;
  const tss: string[] = [];
  const say = (t: number, kind: "person" | "agent", author: string, text: string, extra: Record<string, unknown> = {}) => {
    const at = String(++ts);
    tss.push(at);
    store.insertMessage({ ...newMessage(t, at, kind, author, text), at: ts * 10, ...extra } as ReturnType<typeof newMessage>);
    return at;
  };
  for (let i = 0; i < 260; i++) {
    const at = say(thread, i % 3 === 0 ? "agent" : "person", i % 3 === 0 ? "s" : i < 30 ? "early@x" : "a@x", `message ${i}`,
      i % 17 === 0 ? { letter: { way: "out", title: "To Y", link: null } } : {});
    if (i % 23 === 0) store.editMessage("ember", "CHAT", "long", at, `message ${i}, edited`);
  }
  say(short, "person", "a@x", "only one");
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const t of [thread, short, 9999]) for (const limit of [0, 1, 5, 50, 200, 300, -1])
      out.push(await read(readers, "latestMessages", { thread: t, limit }));
    for (const before of [tss[100], tss[5], tss.at(-2), "nope", null]) for (const limit of [3, 80])
      out.push(await read(readers, "chatHistoryMessages", { thread, before, limit }));
    for (const [author, agentOnly] of [["s", true], ["s", false], ["a@x", true], ["a@x", false], ["early@x", false], ["nobody", false]] as const)
      out.push(await read(readers, "openedChatSaid", { thread, author, agentOnly }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["message 259", "edited", "\"letter\""]) assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
