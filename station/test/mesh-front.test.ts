import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { connect, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { createInterface } from "node:readline";
import { withFront } from "../src/mesh/front.ts";
import { loadMesh } from "../src/mesh/native.ts";

const PIPE_END = 0xffff_fffe;

function streamHead(conn: number, id: number, outgoing: 0 | 1): Buffer {
  const head = Buffer.alloc(17);
  head.writeBigUInt64BE(BigInt(conn), 0);
  head.writeBigUInt64BE(BigInt(id), 8);
  head[16] = outgoing;
  return head;
}

function frame(data: Buffer): Buffer {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  return Buffer.concat([head, data]);
}

function endFrame(): Buffer {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(PIPE_END, 0);
  return head;
}

test("Front closes half-open stream sockets on abrupt end and connection close, and drops late arrivals", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "front-forget-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const socketPath = join(dir, "front.sock");

  let streamsPath = "";
  const pendingClosed = new Map<number, (ok: unknown) => void>();
  let resolveAccept!: (ok: unknown) => void;
  const server = createServer((c) => {
    createInterface({ input: c }).on("line", (line) => {
      const msg = JSON.parse(line) as { id: number; op: string; conn?: number; streams?: string };
      if (msg.op === "bind") {
        streamsPath = msg.streams!;
        c.write(JSON.stringify({ id: msg.id, ok: { id: "00".repeat(32), sockets: ["127.0.0.1:1"] } }) + "\n");
      } else if (msg.op === "relayStatus") {
        c.write(JSON.stringify({ id: msg.id, ok: [] }) + "\n");
      } else if (msg.op === "accept") {
        resolveAccept = (ok) => c.write(JSON.stringify({ id: msg.id, ok }) + "\n");
      } else if (msg.op === "conn.closed") {
        pendingClosed.set(msg.conn!, (ok) => c.write(JSON.stringify({ id: msg.id, ok }) + "\n"));
      } else if (msg.op === "close") {
        c.write(JSON.stringify({ id: msg.id, ok: null }) + "\n");
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(socketPath, resolve));
  t.after(() => server.close());

  const mesh = withFront(loadMesh(), socketPath);
  const endpoint = await mesh.bind({ secretKey: Buffer.alloc(32), alpns: [Buffer.from("stillfail/test")], relayUrls: [], discovery: false });
  t.after(() => endpoint.close().catch(() => {}));

  const accepting = endpoint.accept();
  while (!resolveAccept) await new Promise((r) => setImmediate(r));
  resolveAccept({ conn: 1, remote: "11".repeat(32), alpn: "74657374", via: null, paths: [], stats: { txBytes: 0, rxBytes: 0 } });
  const conn = (await accepting)!;

  // 1. Stream 10 ends abruptly from front without PIPE_END/PIPE_FAILED: Node half closes too.
  const s10 = connect(streamsPath);
  const s10Closed = new Promise<void>((resolve) => s10.once("close", () => resolve()));
  await new Promise<void>((resolve) => s10.once("connect", resolve));
  s10.write(Buffer.concat([streamHead(1, 10, 0), frame(Buffer.from("hi"))]));
  s10.end();
  const st10 = (await conn.acceptBi())!;
  assert.equal((await st10.read())?.toString(), "hi");
  await assert.rejects(st10.read());
  await s10Closed;

  // 2. Stream 11 got PIPE_END while Node left it un-finished; conn.closed -> forget(1) ends Node's write side.
  const s11 = connect(streamsPath);
  const s11EndedFromNode = new Promise<void>((resolve) => s11.once("end", () => { s11.end(); resolve(); }));
  const s11Closed = new Promise<void>((resolve) => s11.once("close", () => resolve()));
  await new Promise<void>((resolve) => s11.once("connect", resolve));
  s11.write(Buffer.concat([streamHead(1, 11, 0), frame(Buffer.from("ok")), endFrame()]));
  const st11 = (await conn.acceptBi())!;
  assert.equal((await st11.read())?.toString(), "ok");
  assert.equal(await st11.read(), null);

  while (!pendingClosed.has(1)) await new Promise((r) => setImmediate(r));
  pendingClosed.get(1)!({ kind: "peer", reason: "idle", text: "idle" });
  await conn.closed();
  await s11EndedFromNode;
  await s11Closed;

  // 3. Late incoming stream arriving after forget(1) is destroyed immediately.
  const late = connect(streamsPath);
  const lateClosed = new Promise<void>((resolve) => late.once("close", () => resolve()));
  await new Promise<void>((resolve) => late.once("connect", resolve));
  late.write(Buffer.concat([streamHead(1, 12, 0), frame(Buffer.from("late"))]));
  await lateClosed;
});
