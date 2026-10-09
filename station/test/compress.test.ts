// Answers compressed for a client that asks so (src/mesh/compress.ts): JSON and text, whole or an event stream flushed
// after each event; nothing for one that does not ask, for a preview, for pictures, or for what is too small to gain.
import assert from "node:assert/strict";
import { test } from "node:test";
import { createZstdDecompress, zstdDecompressSync } from "node:zlib";
import type { Answer } from "../src/api/request.ts";
import { ZSTD, compressed } from "../src/mesh/compress.ts";

const asks = { "accept-encoding": `gzip, ${ZSTD}` };
const json = (body: unknown): Answer => ({ status: 200, headers: { "content-type": "application/json" }, body: Buffer.from(JSON.stringify(body)) });
const rows = Array.from({ length: 200 }, (_, i) => ({ id: String(i), title: `部署 station ${i}`, agents: [], lastActiveAt: 1791478600000 + i }));

test("a whole JSON answer is compressed for a client that asks so, and only then", async () => {
  const answer = json(rows);
  const sent = await compressed(answer, asks, "/chats");
  assert.equal(sent.headers["content-encoding"], ZSTD);
  assert.deepEqual(JSON.parse(zstdDecompressSync(sent.body as Buffer).toString()), rows);
  assert.ok((sent.body as Buffer).length < (answer.body as Buffer).length / 5);
  // Not asked, a preview's, a picture, or small: as it is.
  assert.equal(await compressed(answer, {}, "/chats"), answer);
  assert.equal(await compressed(answer, { "accept-encoding": "gzip" }, "/chats"), answer);
  const page = { ...answer, headers: { "content-type": "text/html" } };
  assert.equal(await compressed(page, asks, "/preview/5173/index.html"), page);
  const picture = { ...answer, headers: { "content-type": "image/png" } };
  assert.equal(await compressed(picture, asks, "/sessions/k/files"), picture);
  const small = json({ ok: true });
  assert.equal(await compressed(small, asks, "/threads/1"), small);
});

test("several reads in one are compressed harder: nobody waits on them", async () => {
  const pages = Array.from({ length: 40 }, (_, p) => ({ status: 200, body: { last: 50, entries: Array.from({ length: 50 }, (_, i) => ({ n: i + 1, thread: p, kind: "message", authorKind: i % 2 ? "agent" : "person", author: i % 2 ? "ember:c-00be6a2584" : "a@x.com", text: `第 ${p}.${i} 条：${"部署 station 之后看日志 ".repeat(1 + ((p * 7 + i) % 5))}${(p * 131 + i * 17) % 997}`, attachments: [], quotes: [], at: 1791478600000 + p * 1000 + i })) } }));
  const answer = json({ answers: pages });
  const batch = await compressed(answer, asks, "/batch");
  const one = await compressed(answer, asks, "/threads/1/entries");
  assert.deepEqual(JSON.parse(zstdDecompressSync(batch.body as Buffer).toString()), { answers: pages });
  assert.ok((batch.body as Buffer).length < (one.body as Buffer).length, `${(batch.body as Buffer).length} < ${(one.body as Buffer).length}`);
});

test("an event stream is compressed event by event, each whole as it arrives, and let go of at once", async () => {
  const events = [
    ...Array.from({ length: 50 }, (_, i) => `id: 1f2e3d4c.${i}\nevent: session\ndata: ${JSON.stringify({ key: `ember:c-${i % 5}`, turns: i, process: "warm" })}\n\n`),
    // One far bigger than what a stream holds back unread.
    `event: live\ndata: ${JSON.stringify({ entries: Array.from({ length: 4000 }, (_, i) => ({ kind: "tool_call", text: `step ${i} ${"x".repeat(200)}` })) })}\n\n`,
    "event: session\ndata: {}\n\n",
  ];
  let at = 0;
  let let_go = false;
  const source: AsyncIterableIterator<Buffer> = {
    [Symbol.asyncIterator]: () => source,
    next: async () => (at < events.length ? { done: false, value: Buffer.from(events[at++]!) } : new Promise(() => {})),
    return: async () => {
      let_go = true;
      return { done: true, value: undefined };
    },
  };
  const sent = await compressed({ status: 200, headers: { "content-type": "text/event-stream" }, body: source }, asks, "/events");
  assert.equal(sent.headers["content-encoding"], ZSTD);
  const it = (sent.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  // As a client reads it: each piece as it comes.
  const read = createZstdDecompress();
  let got = "";
  read.on("data", (part: Buffer) => (got += part.toString()));
  let sentBytes = 0;
  let raw = 0;
  for (let i = 0; i < events.length; i++) {
    const next = await it.next();
    assert.equal(next.done, false);
    sentBytes += next.value.length;
    raw += Buffer.byteLength(events[i]!);
    await new Promise((resolve) => read.write(next.value, resolve));
    // All that came so far reads as all the events so far: none waits for the next.
    assert.equal(got, events.slice(0, i + 1).join(""));
  }
  assert.ok(sentBytes < raw / 5);
  read.close();
  await it.return?.();
  assert.equal(let_go, true);
});
