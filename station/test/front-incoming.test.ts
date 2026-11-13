// The streams a connection's other end opens, as the front hands them (src/mesh/front.ts `Incoming`): each on a
// socket of its own, so they come in any order; taken in the order they were opened. 2026-11-13: a device's requests,
// opened right after its credential stream, came first and were refused as its credential (`malformed credential`).
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Front, Incoming } from "../src/mesh/front.ts";

function stream(id: number, index?: number) {
  const destroyed = { yes: false };
  const socket = { destroy: () => void (destroyed.yes = true) } as unknown as Socket;
  return { came: { socket, carry: Buffer.alloc(0), id, ...(index === undefined ? {} : { index }) }, destroyed };
}

async function taken(incoming: Incoming, n: number): Promise<number[]> {
  const ids: number[] = [];
  for (let i = 0; i < n; i++) ids.push((await incoming.take())!.id);
  return ids;
}

test("streams that come out of order are taken in the order they were opened", async () => {
  const incoming = new Incoming();
  // Opened 0 (the credential), 1, 2, 3; their sockets came 2, 1, 3, 0.
  incoming.give(stream(12, 2).came);
  incoming.give(stream(11, 1).came);
  incoming.give(stream(13, 3).came);
  incoming.give(stream(10, 0).came);
  assert.deepEqual(await taken(incoming, 4), [10, 11, 12, 13]);
});

test("one asked for before it came is given once those before it came", async () => {
  const incoming = new Incoming();
  const first = incoming.take();
  incoming.give(stream(21, 1).came);
  let settled = false;
  void first.then(() => (settled = true));
  await Promise.resolve();
  assert.equal(settled, false, "the request is not taken ahead of the credential");
  incoming.give(stream(20, 0).came);
  assert.equal((await first)!.id, 20);
  assert.equal((await incoming.take())!.id, 21);
});

test("a front from before the index: streams go as they came", async () => {
  const incoming = new Incoming();
  incoming.give(stream(31).came);
  incoming.give(stream(30).came);
  assert.deepEqual(await taken(incoming, 2), [31, 30]);
});

test("the connection gone: those waiting for one before them are let go", async () => {
  const incoming = new Incoming();
  const waiting = stream(41, 1);
  incoming.give(waiting.came);
  incoming.end();
  assert.equal(waiting.destroyed.yes, true);
  assert.equal(await incoming.take(), null);
});

test("the front ending with EPIPE on its control socket settles gone without an unhandled readline error", async () => {
  const dir = await mkdtemp(join(tmpdir(), "front-epipe-"));
  const sock = join(dir, "front.sock");
  let accepted: Socket | undefined;
  const server = createServer((s) => { accepted = s; });
  await new Promise<void>((resolve) => server.listen(sock, resolve));
  try {
    const front = await Front.open(sock);
    const pending = front.ask("endpoint.addresses");
    accepted!.destroy();
    await front.gone;
    await assert.rejects(pending, /the front is gone/);
    front.close();
  } finally {
    server.close();
    await rm(dir, { recursive: true, force: true });
  }
});
