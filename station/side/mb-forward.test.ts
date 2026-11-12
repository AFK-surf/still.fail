// The MoonBit program serving a listening socket by carrying each connection to a port of this machine (station/mb's
// src/front `forward`, through the shell's `tcp.listen`, `tcp.accept`, `tcp.open` asked as it waits for none of them):
// many connections at once, a megabyte each way on each, each side's end carried as it comes, and one whose other end
// is not there closed. Real sockets and a real process: the side run's.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { type AddressInfo, connect, createServer, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";

const binary = mbReaderBinary();
const skip = binary === null ? "the MoonBit program is not built here (station/mb/build.sh)" : false;

/// What a socket sends until it ends.
function all(s: Socket): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const parts: Buffer[] = [];
    s.on("data", (d) => parts.push(d));
    s.on("end", () => resolve(Buffer.concat(parts)));
    s.on("error", reject);
  });
}

/// The program forwarding a port of its own to `to`, and that port.
async function forwarder(to: number): Promise<{ port: number; stop: () => Promise<number> }> {
  const p = new MbProcess(binary!, ["--builder", "forward", "--listen-port", "0", "--to", String(to), "--shell-dir", mkdtempSync(join(tmpdir(), "mb-forward-"))]);
  const port = await new Promise<number>((resolve, reject) => {
    p.once("message", (m: { listening?: number }) => (typeof m.listening === "number" ? resolve(m.listening) : reject(new Error(JSON.stringify(m)))));
    p.once("exit", (code: number) => reject(new Error(`ended (${code})`)));
  });
  return { port, stop: () => p.terminate() };
}

test("connections carried both ways, many at once, each end as it comes", { skip }, async () => {
  // a server that takes all a client sends, then answers with it backwards and a word, and ends (its side left open as
  // the client ends its own: half open, as the forwarder carries each end alone)
  const server = createServer({ allowHalfOpen: true }, (s) => void all(s).then((got) => s.end(Buffer.concat([Buffer.from(got).reverse(), Buffer.from("|done")]))));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const f = await forwarder((server.address() as AddressInfo).port);
  try {
    const sent = Array.from({ length: 24 }, (_, i) => randomBytes(i % 3 === 0 ? 1 << 20 : 1000 + i));
    const back = await Promise.all(sent.map((bytes) => new Promise<Buffer>((resolve, reject) => {
      const c = connect(f.port, "127.0.0.1", () => c.end(bytes));
      all(c).then(resolve, reject);
    })));
    back.forEach((b, i) => {
      const want = Buffer.concat([Buffer.from(sent[i]!).reverse(), Buffer.from("|done")]);
      assert.ok(b.equals(want), `connection ${i}: ${b.length} bytes of ${want.length}, first differing at ${b.findIndex((x, j) => x !== want[j])}`);
    });
  } finally {
    await f.stop();
    server.close();
  }
});

test("a connection whose other end is not there is closed", { skip }, async () => {
  // (a port just let go: nothing listens there)
  const gone = createServer();
  await new Promise<void>((r) => gone.listen(0, "127.0.0.1", r));
  const port = (gone.address() as AddressInfo).port;
  await new Promise<void>((r) => gone.close(() => r()));
  const f = await forwarder(port);
  try {
    const c = connect(f.port, "127.0.0.1");
    const got = await all(c).catch(() => Buffer.alloc(0));
    assert.equal(got.length, 0);
  } finally {
    await f.stop();
  }
});
