// The requests the MoonBit program answers itself (station/src/mesh/served.ts, station/mb's reader `--serve`): a
// device's stream asking a route given to the front (front.ts `route`, client/shell `conn.hand`) goes to the program,
// which answers it as the admin API does; every other stream comes to Node as before, in the order the device opened
// them, the one taken by the program not waited for. Real processes and sockets: the side run's.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdDecompressSync } from "node:zlib";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { withFront } from "../src/mesh/front.ts";
import { SERVED_ROUTES, Served } from "../src/mesh/served.ts";
import { RUNTIME_KINDS } from "../src/agents/runtime.ts";
import { type Endpoint, type Stream, loadMesh } from "../src/mesh/native.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();
const skip = binary === null ? "the MoonBit program is not built here (station/mb/build.sh)" : false;
const ALPN = Buffer.from("stillfail/test/served");
const OTHER = Buffer.from("stillfail/test/other");

async function front(dir: string): Promise<{ socket: string; stop: () => Promise<number> }> {
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

/// A request on a stream of its own: its head line, then its answer's head and body.
async function ask(conn: { openBi(): Promise<Stream> }, head: object): Promise<{ head: any; body: Buffer }> {
  const s = await conn.openBi();
  await s.write(Buffer.from(`${JSON.stringify(head)}\n`));
  await s.finish();
  const all = await readAll(s);
  const at = all.indexOf(10);
  return { head: JSON.parse(all.subarray(0, at).toString()), body: all.subarray(at + 1) };
}

const addrOf = (e: Endpoint) => ({ id: e.id(), ips: e.sockets().filter((s) => /^\d/.test(s)).map((s) => s.replace(/^0\.0\.0\.0/, "127.0.0.1")) });

test("a routed request is answered by the MoonBit program as the admin API answers it; the rest come to Node in order", { skip }, async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "mbsv-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const data = join(dir, "data");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  // (chats of sessions, so the list has rows to compress)
  for (let k = 0; k < 6; k++) {
    store.insertSession({ key: `s${k}`, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: `s${k}`, createdAt: 1, lastActiveAt: 1000 + k } as Parameters<Store["insertSession"]>[0]);
    const t = store.openThread("ember", "CHAT", `c${k}`, `Served ${k}`, null).id;
    store.joinThread(t, `s${k}`, "ember");
    store.insertMessage({ ...newMessage(t, "1", "person", "p@x", `hello ${k} ${"words ".repeat(30)}`), at: 100 + k } as ReturnType<typeof newMessage>);
  }
  const thread = store.openThread("ember", "CHAT", "c", "Served", null).id;
  for (let i = 0; i < 40; i++) store.insertMessage({ ...newMessage(thread, String(i + 1), "person", "p@x", `message ${i} ${"words ".repeat(20)}`), at: (i + 1) * 10 } as ReturnType<typeof newMessage>);
  t.after(() => store.close());

  const f = await front(dir);
  t.after(() => f.stop());
  const mesh = withFront(loadMesh(), f.socket);
  const station = await mesh.bind({ secretKey: Buffer.alloc(32, 7), alpns: [ALPN, OTHER], relayUrls: [], discovery: false });
  t.after(() => station.close());
  const device = await loadMesh().bind({ secretKey: Buffer.alloc(32, 9), alpns: [ALPN, OTHER], relayUrls: [], discovery: false });
  t.after(() => device.close());

  const viewer = { email: "p@x", name: "P", workspace: "ws", role: "owner", home: true };
  const given: { head: any; body: string }[] = [];
  const builds: (number | null)[] = [];
  const served = new Served(binary!, data, async (v, head, body) => {
    given.push({ head, body: body.toString() });
    assert.deepEqual(v, viewer);
    return { status: 200, headers: { "content-type": "application/json" }, body: Buffer.from('{"from":"node"}') };
  }, (_, build) => builds.push(build));
  t.after(() => served.close());
  const paths = await served.start();
  assert.equal(await station.route!(ALPN, paths, SERVED_ROUTES), true);

  const accepted = station.accept();
  const theirs = await device.connect(addrOf(station), ALPN);
  const conn = (await accepted)!;
  assert.equal(typeof conn.handed, "number");

  // first a stream as a credential's (Node's), then a routed request, then one of Node's: Node takes the first and the
  // third, in that order, the second never waited for
  const first = await theirs.openBi();
  await first.write(Buffer.from('{"hello":1}\n'));
  const routedHead = { method: "GET", path: "/admin/api/chats?shared=1", headers: { "stillfail-build": "0.1.9200", "stillfail-runtimes": RUNTIME_KINDS.join(","), "accept-encoding": "zstd", "stillfail-lang": "en" } };
  const routed = ask(theirs, routedHead);
  const third = await theirs.openBi();
  await third.write(Buffer.from('{"method":"GET","path":"/admin/api/sessions"}\n'));
  const a = (await conn.acceptBi())!;
  const c = (await conn.acceptBi())!;
  const lineOf = async (s: Stream) => (await s.read())!.toString();
  assert.equal(await lineOf(a), '{"hello":1}\n');
  assert.equal(await lineOf(c), '{"method":"GET","path":"/admin/api/sessions"}\n');

  // the member said once the connection is let in: the request waits for it
  served.viewer(conn.handed!, viewer);
  const answer = await routed;
  const said = `${JSON.stringify(answer.head)}, ${answer.body.length} bytes: ${answer.body.subarray(0, 200).toString()}`;
  assert.equal(answer.head.status, 200, said);
  assert.equal(answer.head.headers["content-encoding"], "zstd", said);
  assert.equal(answer.head.headers["stillfail-idempotent"], "1");
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  // (as the admin API learns people's names from who asks)
  worker.names.set(viewer.email, viewer.name);
  t.after(() => worker.close());
  const theirsText = await worker.read("sharedChats", { viewer, sessions: null, threads: null }, "en");
  const ours = JSON.parse(zstdDecompressSync(answer.body).toString());
  assert.ok(Array.isArray(ours) ? ours.length > 0 : Object.keys(ours).length > 0, said);
  const diffAt = (a: unknown, b: unknown, at = ""): string | null => {
    if (JSON.stringify(a) === JSON.stringify(b)) return null;
    if (a && b && typeof a === "object" && typeof b === "object") {
      for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
        const d = diffAt((a as any)[k], (b as any)[k], `${at}.${k}`);
        if (d !== null) return d;
      }
    }
    return `${at}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`;
  };
  assert.deepEqual(ours, JSON.parse(theirsText), diffAt(ours, JSON.parse(theirsText)) ?? "");
  assert.deepEqual(builds, [9200]);

  // a core that does not take every runtime: given to Node, its answer said as Node made it
  const old = await ask(theirs, { ...routedHead, headers: { ...routedHead.headers, "stillfail-runtimes": "claude" } });
  assert.equal(old.head.status, 200);
  assert.equal(old.body.toString(), '{"from":"node"}');
  assert.equal(given.length, 1);
  assert.equal(given[0]!.head.path, "/admin/api/chats?shared=1");

  // a core under the floor: told to update, by the program
  const tooOld = await ask(theirs, { ...routedHead, headers: { ...routedHead.headers, "stillfail-build": "0.1.1001" } });
  assert.equal(tooOld.head.status, 426);
  assert.equal(JSON.parse(tooOld.body.toString()).update, true);

  // another protocol's connections are not routed: its request comes to Node
  const acceptedOther = station.accept();
  const other = await device.connect(addrOf(station), OTHER);
  const otherConn = (await acceptedOther)!;
  const s = await other.openBi();
  await s.write(Buffer.from('{"x":0}\n'));
  const o = await other.openBi();
  await o.write(Buffer.from(`${JSON.stringify(routedHead)}\n`));
  const o1 = (await otherConn.acceptBi())!;
  const o2 = (await otherConn.acceptBi())!;
  assert.equal(await lineOf(o1), '{"x":0}\n');
  assert.equal(JSON.parse(await lineOf(o2)).path, "/admin/api/chats?shared=1");
});
