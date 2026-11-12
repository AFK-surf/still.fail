// The station's endpoint kept by the MoonBit front (station/mb's src/front/mesh.mbt, station/src/mesh/front.ts) against
// the addon's own: the same scenario run on each, a device's endpoint (the addon's) dialing the station, and what each
// side saw compared, step for step: who connected and on what, a stream's bytes both ways, its end, a reset and its
// code, what a stream's end is acknowledged with, a stream one way, why a connection went. Then what only the front
// does: a second Node binding takes the connections that come from then on, the first keeps its own, and closing its
// endpoint closes only those. And a front that ended, another started in its place: the Node links to it again, bound
// as before, and takes what comes. Real processes and sockets: the side run's.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { createSocket } from "node:dgram";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { withFront } from "../src/mesh/front.ts";
import { hearLines } from "../src/ops/log.ts";
import { type Connection, type Endpoint, type Mesh, type Stream, loadMesh } from "../src/mesh/native.ts";

const binary = mbReaderBinary();
const skip = binary === null ? "the MoonBit program is not built here (station/mb/build.sh)" : false;
const ALPN = Buffer.from("stillfail/test/1");

/// The front, listening at a socket of its own; what stops it.
async function front(at?: string): Promise<{ socket: string; stop: () => Promise<number> }> {
  const dir = at ?? mkdtempSync(join(tmpdir(), "mbm-"));
  const socket = join(dir, "front.sock");
  const p = new MbProcess(binary!, ["--builder", "mesh", "--socket", socket, "--shell-dir", join(dir, "shell")]);
  await new Promise<void>((resolve, reject) => {
    p.once("message", (m: { listening?: string }) => (m.listening === socket ? resolve() : reject(new Error(JSON.stringify(m)))));
    p.once("exit", (code: number) => reject(new Error(`ended (${code})`)));
  });
  return { socket, stop: () => p.terminate() };
}

async function readAll(s: Stream): Promise<Buffer> {
  const parts: Buffer[] = [];
  for (let b = await s.read(); b !== null; b = await s.read()) parts.push(b);
  return Buffer.concat(parts);
}

const bindOn = (mesh: Mesh, key: Buffer) => mesh.bind({ secretKey: key, alpns: [ALPN], relayUrls: [], discovery: false });
const addrOf = (e: Endpoint) => ({ id: e.id(), ips: e.sockets().filter((s) => s.startsWith("0.0.0.0") || /^\d/.test(s)).map((s) => s.replace(/^0\.0\.0\.0/, "127.0.0.1")) });

/// What a station's endpoint and a device's see of one exchange: the same on the addon and on the front.
async function scenario(station: Endpoint, device: Endpoint): Promise<unknown[]> {
  const seen: unknown[] = [];
  const accepted = station.accept();
  const theirs = await device.connect(addrOf(station), ALPN);
  const conn = (await accepted)!;
  seen.push({ remote: conn.remoteId() === device.id(), alpn: conn.alpn().toString(), closed: conn.isClosed() });

  // a stream the device opens: a megabyte there, the same backwards and a word back, each end as it comes
  const sent = randomBytes(1 << 20);
  const opened = await theirs.openBi();
  const writing = opened.write(sent).then(() => opened.finish());
  const s = (await conn.acceptBi())!;
  const got = await readAll(s);
  await writing;
  seen.push({ got: got.equals(sent) });
  await s.write(Buffer.concat([Buffer.from(got).reverse(), Buffer.from("|done")]));
  await s.finish();
  const back = await readAll(opened);
  seen.push({ back: back.equals(Buffer.concat([Buffer.from(sent).reverse(), Buffer.from("|done")])), ackd: await s.stopped() });

  // a stream the station opens, reset by it: the device's read fails, its write is told the code
  const mine = await conn.openBi();
  await mine.write(Buffer.from("hello"));
  const theirStream = (await theirs.acceptBi())!;
  seen.push({ first: (await theirStream.read())?.toString() });
  await mine.reset(7);
  seen.push({ readAfterReset: await mine.read() });
  seen.push({ theirRead: await theirStream.read().then((b) => `bytes ${b?.length}`, (e: Error) => `failed: ${e.message}`) });

  // the device stops reading one: the station's stopped says the code
  const told = await conn.openBi();
  await told.write(Buffer.from("x"));
  const stopping = (await theirs.acceptBi())!;
  await stopping.read();
  await stopping.reset(9);
  seen.push({ stopped: await told.stopped() });

  // a stream one way
  const uni = await (conn as Connection & { openUni(): Promise<{ write(b: Buffer): Promise<void>; finish(): Promise<void>; stopped(): Promise<number | null> }> }).openUni();
  await uni.write(Buffer.from("one way"));
  await uni.finish();

  // the device closes the connection: why, on the station's side
  theirs.close(3, "bye");
  seen.push({ closed: await conn.closed(), isClosed: conn.isClosed() });
  seen.push({ acceptAfter: await conn.acceptBi() });
  return seen;
}

test("the front's endpoint is seen as the addon's, step for step", { skip }, async () => {
  const addon = loadMesh();
  const f = await front();
  try {
    const runs: unknown[][] = [];
    for (const mesh of [addon, withFront(addon, f.socket)]) {
      const station = await bindOn(mesh, randomBytes(32));
      const device = await bindOn(addon, randomBytes(32));
      try {
        runs.push(await scenario(station, device));
      } finally {
        await device.close();
        await station.close();
      }
    }
    assert.deepEqual(runs[1], runs[0]);
  } finally {
    await f.stop();
  }
});

test("a Node binding again takes what comes from then on; the first keeps its own until it closes", { skip }, async () => {
  const addon = loadMesh();
  const f = await front();
  const key = randomBytes(32);
  try {
    const first = await bindOn(withFront(addon, f.socket), key);
    const device = await bindOn(addon, randomBytes(32));
    const one = first.accept();
    const dialedOne = await device.connect(addrOf(first), ALPN);
    const conn1 = (await one)!;
    assert.equal(conn1.remoteId(), device.id());

    // the next Node: the same endpoint (its id and where it listens), the next connection its own
    const second = await bindOn(withFront(addon, f.socket), key);
    assert.equal(second.id(), first.id());
    assert.deepEqual(second.sockets(), first.sockets());
    const device2 = await bindOn(addon, randomBytes(32));
    const two = second.accept();
    const dialedTwo = await device2.connect(addrOf(second), ALPN);
    const conn2 = (await two)!;
    assert.equal(conn2.remoteId(), device2.id());

    // the first's connection still carries; closing the first's endpoint closes it alone
    const s = await dialedOne.openBi();
    await s.write(Buffer.from("still here"));
    await s.finish();
    assert.equal((await readAll((await conn1.acceptBi())!)).toString(), "still here");
    await first.close();
    await dialedOne.closed();
    assert.equal(dialedTwo.isClosed(), false);
    const t = await dialedTwo.openBi();
    await t.write(Buffer.from("on the second"));
    await t.finish();
    assert.equal((await readAll((await conn2.acceptBi())!)).toString(), "on the second");
    await device.close();
    await device2.close();
    await second.close();
  } finally {
    await f.stop();
  }
});

test("a front can bind a fixed port after an older endpoint releases it", { skip }, async () => {
  const addon = loadMesh();
  const f = await front();
  const old = createSocket("udp4");
  await new Promise<void>((resolve) => old.bind(0, "127.0.0.1", resolve));
  let oldClosed = false;
  try {
    const addr = `127.0.0.1:${old.address().port}`;
    const options = { secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: addr };
    const bind = () => withFront(addon, f.socket).bind(options);
    await assert.rejects(bind());
    await new Promise<void>((resolve) => old.close(resolve));
    oldClosed = true;
    const station = await bind();
    const device = await bindOn(addon, randomBytes(32));
    try {
      assert.ok(station.sockets().includes(addr));
      const accepting = station.accept();
      const connection = await device.connect(addrOf(station), ALPN);
      assert.equal((await accepting)!.remoteId(), device.id());
      connection.close(0, "");
    } finally {
      await device.close();
      await station.close();
    }
  } finally {
    if (!oldClosed) await new Promise<void>((resolve) => old.close(resolve));
    await f.stop();
  }
});

test("a front that ended, another in its place: the Node links to it again and takes what comes", { skip }, async () => {
  const addon = loadMesh();
  const dir = mkdtempSync(join(tmpdir(), "mbm-"));
  let f = await front(dir);
  const key = randomBytes(32);
  const station = await bindOn(withFront(addon, f.socket), key);
  const id = station.id();
  const device = await bindOn(addon, randomBytes(32));
  try {
    const accepting = station.accept();
    // told as it links again (its log's line)
    const linked = new Promise<void>((resolve) => hearLines((l) => void (l.message === "linked to the front again" && resolve())));
    await f.stop();
    f = await front(dir);
    await linked;
    const dialed = await device.connect(addrOf(station), ALPN);
    const conn = (await accepting)!;
    assert.equal(conn.remoteId(), device.id());
    dialed.close(0, "");
    assert.equal(station.id(), id);
  } finally {
    await device.close();
    await station.close();
    await f.stop();
  }
});
