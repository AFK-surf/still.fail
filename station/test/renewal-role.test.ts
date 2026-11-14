// A renewal this station refuses changes nothing of the connection (src/mesh/serve.ts `admission`): a later line on
// the control stream whose credential checks out and whose member the lock then refuses is answered why, and the
// connection goes on as it was let in: the member's workspace, the role their own credential names, its expiry. Until
// 2026-11-14 the role such a line named was kept: a member of an unlocked workspace of a station, with a credential of
// another workspace of that station where the control plane calls them an owner and whose lock does not name their
// device, was answered as an owner of the first from that line on. A renewal let in is taken whole, as before.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test, type TestContext } from "node:test";
import type { Admin } from "../src/api/admin.ts";
import { json, type Request } from "../src/api/request.ts";
import { endpointBytes, entryHash } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { ALPN, Reader, seenDevicesOf, serve, writeLine } from "../src/mesh/serve.ts";
import { wall } from "../src/ops/fibers.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { ed, signed } from "./lock-moved-world.ts";
import { memoryMesh } from "./memory-mesh.ts";

const A = "01HAAAAAAAAAAAAAAAAAAAAAAA";
const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";

// The machine's time and its timers are the test's: once the station is set up, all that arms one here is a
// credential's expiry, and a refused hello's close.
const START = 2_000_000;
let now = START;
mock.method(wall, "now", () => now * 1000);
type Timer = { ms: number; fire: () => void; off: boolean };
const timers: Timer[] = [];
mock.method(wall, "after", (ms: number, fire: () => void) => {
  const timer = { ms, fire, off: false };
  timers.push(timer);
  return () => void (timer.off = true);
});
const armed = () => timers.filter((t) => !t.off);

/// A station at home in A, which has no lock, and joined to B, whose lock it pinned: alice's, her device alone on it.
/// eve's device, connected and not yet said hello: a member of A as the control plane signs it; of B it calls her an
/// owner, and B's lock does not name her device. `own`: a lock of A she signed herself, its owner, her device on it
/// (what A's owner would bring this station to turn A's lock on).
async function setUp(t: TestContext) {
  now = START;
  timers.length = 0;
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [at, device] = await Promise.all([bind(), bind()]);
  const data = mkdtempSync(join(tmpdir(), "renewal-role-"));
  const keys: Record<string, GrantKey> = { [A]: new GrantKey("a"), [B]: new GrantKey("b") };
  writeState(data, {
    origin: "https://app.still.fail", station: at.id(), workspace: A, workspace_name: "A", name: "s0", relay_url: "", relay_urls: [],
    grant_keys: { keys: [keys[A]!.jwk] }, peers: [], revocations: [],
    joined: [{ workspace: B, workspace_name: "B", name: "s0", peers: [], revocations: [], locked: true }],
  });
  const cloud = new Cloud(data, false);
  const alice = { signer: ed(), base: ed() };
  const genesis = signed({ v: 1, ws: B, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [keys[B]!.jwk] },
    members: [{ sub: "alice", email: "alice@x", role: "owner" }],
    devices: [{ id: alice.base.hex, sub: "alice", kind: "app", label: "alice", sign_key: alice.signer.id }],
    passkeys: [], stations: [{ key: at.id(), name: "s0" }], gateways: [],
  } }, alice.signer);
  cloud.takeLock([genesis], B);
  const eve = { signer: ed(), base: ed() };
  const own = signed({ v: 1, ws: A, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "eve", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [keys[A]!.jwk] },
    members: [{ sub: "eve", email: "eve@x", role: "owner" }],
    devices: [{ id: eve.base.hex, sub: "eve", kind: "app", label: "eve", sign_key: eve.signer.id }],
    passkeys: [], stations: [{ key: at.id(), name: "s0" }], gateways: [],
  } }, eve.signer);
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [A, B], "in both");
  assert.deepEqual([cloud.locked(), cloud.locked(B)?.state?.genesis], [null, entryHash(genesis)], "A with no lock, B's pinned");
  // (what pinning armed, the debounce of its own write, is over)
  for (const timer of timers.splice(0)) timer.fire();
  // What a request is answered: who the station takes its asker for.
  const admin = { handle: async (r: Request) => json(200, JSON.stringify({ sub: r.viewer.sub, workspace: r.viewer.workspace, role: r.viewer.role })) } as unknown as Admin;
  void (async () => {
    for (;;) {
      const conn = await at.accept();
      if (!conn) return;
      void serve({ cloud, admin, up: () => true }, conn).catch(() => {});
    }
  })();
  t.after(async () => {
    cloud.close();
    await Promise.all([at.close(), device.close()]);
    rmSync(data, { recursive: true, force: true });
  });
  const conn = await device.connect({ id: at.id() }, ALPN);
  const first = await conn.openBi();
  const control = new Reader(first);
  /// eve's credential of `ws`, naming `role`, good for `secs` from now.
  const credential = (ws: string, role: string, secs: number) =>
    keys[ws]!.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: "eve", email: "eve@x", name: "eve", ws, role, device: device.id(), sid: "s", iat: now, exp: now + secs });
  /// Her device's proof of this endpoint in A, as an app's hello carries it.
  const lock = { device: eve.base.hex, proof: eve.base.sign(endpointBytes(A, device.id())) };
  /// A line on the control stream (the hello, then renewals) and what it is answered.
  const say = async (line: unknown) => {
    await writeLine(first, line);
    return control.line();
  };
  /// A request on a stream of its own: its status and what it is answered.
  const ask = async (method: string, path: string, body = "{}") => {
    const stream = await conn.openBi();
    await writeLine(stream, { method, path: `/admin/api${path}`, headers: {} });
    await stream.write(Buffer.from(body));
    await stream.finish();
    const reader = new Reader(stream);
    const head = await reader.line();
    return [head.status, JSON.parse((await reader.rest()).toString())];
  };
  return { cloud, conn, device, genesis, own, lock, credential, say, ask };
}

test("a renewal the lock refuses, of another workspace where its credential names an owner: the connection is the member it was, in its workspace, until its own credential runs out", async (t) => {
  const { cloud, conn, device, own, lock, credential, say, ask } = await setUp(t);
  assert.deepEqual(await say({ credential: credential(A, "member", 600), protocol: 2, lock }), { ok: true, station: "s0", expires_at: START + 600 });
  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "member" }]);
  assert.equal((await ask("PUT", "/station-mark", '{"name":"eve\'s"}'))[0], 403, "a member changes no station's name");
  const expiry = armed();
  assert.deepEqual(expiry.map((x) => x.ms), [600_000 + 50]);

  // B's credential checks out (the station noted the device as come to B) and B's lock refuses the device.
  const refused = await say({ credential: credential(B, "owner", 3600) });
  assert.deepEqual([typeof refused.error, refused.ok, refused.expires_at], ["string", undefined, undefined], "answered why, and not renewed");
  assert.deepEqual(seenDevicesOf(cloud).of(B, now, "eve", false).map((d) => d.device), [device.id()], "its credential checked out");

  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "member" }], "the member of A it was let in as");
  assert.equal((await ask("PUT", "/station-mark", '{"name":"eve\'s"}'))[0], 403, "still changes no station's name");
  assert.equal((await ask("POST", "/lock", JSON.stringify({ entries: [own] })))[0], 403, "nor turns A's lock on with one of her own");
  assert.equal(cloud.locked(), null, "A with no lock still");
  assert.deepEqual(armed(), expiry, "its expiry the one armed at its hello");

  now = START + 600;
  expiry[0]!.fire();
  assert.equal(await conn.closed(), "credential_expired", "ended as the credential of its hello runs out");
});

test("a renewal let in is taken whole, as before: the role it names and its expiry; one refused after it leaves those", async (t) => {
  const { conn, credential, say, ask } = await setUp(t);
  assert.equal((await say({ credential: credential(A, "member", 600), protocol: 2 })).ok, true);
  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "member" }]);
  const [first] = armed();
  // The control plane made eve an admin of A since: her next credential says so.
  assert.deepEqual(await say({ credential: credential(A, "admin", 3600) }), { ok: true, expires_at: START + 3600 });
  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "admin" }]);
  assert.equal(first!.off, true, "the first credential's expiry called off");
  const expiry = armed();
  assert.deepEqual(expiry.map((x) => x.ms), [3600_000 + 50], "the renewed one's armed");

  assert.equal(typeof (await say({ credential: credential(B, "owner", 7200) })).error, "string");
  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "admin" }], "an admin of A, as its last renewal let in said");
  assert.deepEqual(armed(), expiry);

  // Past the first credential's time the connection goes on; at the renewed one's it ends.
  now = START + 601;
  assert.deepEqual(await ask("GET", "/who"), [200, { sub: "eve", workspace: A, role: "admin" }]);
  now = START + 3600;
  expiry[0]!.fire();
  assert.equal(await conn.closed(), "credential_expired");
});

test("a hello the lock refuses is told as before: the lock's code, how far it goes and its entries, then closed", async (t) => {
  const { conn, genesis, credential, say } = await setUp(t);
  const refused = await say({ credential: credential(B, "owner", 3600), protocol: 2 });
  assert.deepEqual([typeof refused.error, refused.code], ["string", "lock_unconfirmed"]);
  assert.deepEqual(refused.lock, { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) });
  // (the lock's last entries are told only to one whose credential checked out)
  assert.deepEqual(refused.entries, [genesis]);
  // (the close is armed as the hello is refused, before its line is written: armed by the time the line is read)
  assert.deepEqual(armed().map((x) => x.ms), [200]);
  armed()[0]!.fire();
  assert.equal(await conn.closed(), "lock_unconfirmed");
});
