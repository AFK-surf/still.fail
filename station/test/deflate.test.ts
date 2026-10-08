// Answers deflated for a client that asks so (src/mesh/deflate.ts): JSON and text, whole or an event stream flushed after
// each event; nothing for one that does not ask, for a preview, for pictures, or for what is too small to gain.
import assert from "node:assert/strict";
import { test } from "node:test";
import { constants, inflateRawSync } from "node:zlib";
import type { Answer } from "../src/api/request.ts";
import { DEFLATE, deflated } from "../src/mesh/deflate.ts";

const asks = { "accept-encoding": `gzip, ${DEFLATE}` };
const json = (body: unknown): Answer => ({ status: 200, headers: { "content-type": "application/json" }, body: Buffer.from(JSON.stringify(body)) });
const rows = Array.from({ length: 200 }, (_, i) => ({ id: String(i), title: `部署 station ${i}`, agents: [], lastActiveAt: 1791478600000 + i }));

test("a whole JSON answer is deflated for a client that asks so, and only then", async () => {
  const answer = json(rows);
  const sent = await deflated(answer, asks, "/chats");
  assert.equal(sent.headers["content-encoding"], DEFLATE);
  assert.deepEqual(JSON.parse(inflateRawSync(sent.body as Buffer).toString()), rows);
  assert.ok((sent.body as Buffer).length < (answer.body as Buffer).length / 5);
  // Not asked, a preview's, a picture, or small: as it is.
  assert.equal(await deflated(answer, {}, "/chats"), answer);
  assert.equal(await deflated(answer, { "accept-encoding": "gzip" }, "/chats"), answer);
  const page = { ...answer, headers: { "content-type": "text/html" } };
  assert.equal(await deflated(page, asks, "/preview/5173/index.html"), page);
  const picture = { ...answer, headers: { "content-type": "image/png" } };
  assert.equal(await deflated(picture, asks, "/sessions/k/files"), picture);
  const small = json({ ok: true });
  assert.equal(await deflated(small, asks, "/threads/1"), small);
});

test("an event stream is deflated event by event, each whole as it arrives, and let go of at once", async () => {
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
  const sent = await deflated({ status: 200, headers: { "content-type": "text/event-stream" }, body: source }, asks, "/events");
  assert.equal(sent.headers["content-encoding"], DEFLATE);
  const it = (sent.body as AsyncIterable<Buffer>)[Symbol.asyncIterator]();
  const came: Buffer[] = [];
  let raw = 0;
  for (let i = 0; i < events.length; i++) {
    const next = await it.next();
    assert.equal(next.done, false);
    came.push(next.value);
    raw += Buffer.byteLength(events[i]!);
    // All that came so far inflates to all the events so far: none waits for the next.
    assert.equal(inflateRawSync(Buffer.concat(came), { finishFlush: constants.Z_SYNC_FLUSH }).toString(), events.slice(0, i + 1).join(""));
  }
  assert.ok(Buffer.concat(came).length < raw / 5);
  await it.return?.();
  assert.equal(let_go, true);
});
