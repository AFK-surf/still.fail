// A station checks the current personal lock at the real mesh hello and keeps doing so for requests and restarts.
import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { endpointBytes, entryHash, signedBytes, type Entry } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { ALPN, Reader, serve } from "../src/mesh/serve.ts";
import { PersonChains } from "../src/mesh/person-chains.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { memoryMesh } from "./memory-mesh.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ", SUB = "carol";
function key() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("hex");
  return { id: `ed25519:${hex}`, hex, sign: (bytes: Buffer) => sign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof key>;
function entry(by: Key, ws: string, seq: number, prev: string | null, kind: string, body: unknown): Entry {
  const e = { v: 1 as const, ws, seq, prev, at: 1000, kind, body };
  return { ...e, sig: { key: by.id, alg: "Ed25519", sig: by.sign(signedBytes(entryHash(e as Entry))) } };
}
const line = async (stream: { write(bytes: Buffer): Promise<void> }, data: unknown) => stream.write(Buffer.from(JSON.stringify(data) + "\n"));

async function fixture(t: TestContext, revisions = 0, workspaceDeviceIsA = false) {
  const a = key(), aBase = key(), b = key(), bBase = key(), workspaceKey = key(), workspaceBase = key();
  const person: Entry[] = [entry(a, `person:${SUB}`, 0, null, "genesis", { sub: SUB, device: { key: a.id, id: aBase.hex, label: "a" } })];
  const append = (by: Key, kind: string, body: unknown) => person.push(entry(by, `person:${SUB}`, person.length, entryHash(person.at(-1)!), kind, body));
  append(a, "device", { key: b.id, id: bBase.hex, label: "b" });
  for (let i = 0; i < revisions; i++) append(b, "device", { key: b.id, id: bBase.hex, label: `b${i}` });
  let latest = [...person], version = 1;
  const grant = new GrantKey("k1"), mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [station, device] = await Promise.all([bind(), bind()]);
  const data = mkdtempSync(join(tmpdir(), "person-transport-"));
  writeState(data, { origin: "o", station: station.id(), workspace: WS, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [], grant_keys: { keys: [grant.jwk] }, peers: [], revocations: [] });
  let cloud = new Cloud(data, false);
  cloud.setPersonalOnline(true);
  const wsFirst = entry(workspaceKey, WS, 0, null, "genesis", {
    owner: SUB, origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [grant.jwk] },
    members: [{ sub: SUB, email: "c@x", role: "owner" }],
    devices: [{ id: workspaceDeviceIsA ? aBase.hex : workspaceBase.hex, sub: SUB, kind: "app", label: "owner", sign_key: workspaceKey.id }],
    passkeys: [], stations: [{ key: station.id(), name: "s0" }], gateways: [],
  });
  cloud.takeLock([wsFirst, entry(workspaceKey, WS, 1, entryHash(wsFirst), "person", { sub: SUB, person: entryHash(person[0]!) })]);
  t.after(async () => { cloud.close(); await Promise.all([station.close(), device.close()]); });
  let reads = 0;
  const members = { cloud, admin: undefined, up: () => true, personal: async () => { reads++; return { entries: latest, version }; } };
  void (async () => { for (;;) { const conn = await station.accept(); if (!conn) return; void serve(members as never, conn).catch(() => {}); } })();
  const open = async (base: Key, supplied?: Entry[]) => {
    const conn = await device.connect({ id: station.id() }, ALPN);
    const first = await conn.openBi();
    const now = Math.floor(Date.now() / 1000);
    const credential = grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: SUB, email: "c@x", name: "c", ws: WS, role: "owner", device: device.id(), sid: "s", iat: now, exp: now + 3600 });
    const proof = base.sign(endpointBytes(WS, device.id()));
    await line(first, { credential, protocol: 2, lock: { device: base.hex, proof, ...(supplied ? { person: supplied } : {}) } });
    return { conn, first, answer: await new Reader(first).line(), credential };
  };
  return {
    a, aBase, b, bBase, person, append, open, data,
    get cloud() { return cloud; },
    restart: () => { cloud.close(); cloud = new Cloud(data, false); cloud.setPersonalOnline(true); members.cloud = cloud; },
    setLatest: (chain: Entry[]) => { latest = chain; version++; },
    tell: () => cloud.takePersonal(SUB, latest, version), reads: () => reads,
  };
}

test("a personal-lock connection remains admitted for a request and credential renewal", async (t) => {
  const f = await fixture(t);
  const c = await f.open(f.aBase, f.person);
  assert.equal(c.answer.ok, true, JSON.stringify(c.answer));
  const request = await c.conn.openBi();
  await line(request, { method: "GET", path: "/not-admin" });
  assert.equal((await new Reader(request).line()).status, 404, "a valid request reaches the station");
  await line(c.first, { credential: c.credential });
  assert.equal((await new Reader(c.first).line()).ok, true, "renewal retains personal admission");
  c.conn.close(0, "done");
});

test("a station does not admit a removed device bringing an old chain after restart", async (t) => {
  const f = await fixture(t), old = [...f.person];
  f.append(f.b, "device.remove", { key: f.a.id });
  f.setLatest([...f.person]);
  const c = await f.open(f.aBase, old);
  assert.equal(c.answer.ok, undefined);
  assert.equal(c.answer.code, "lock_unconfirmed");
  assert.ok(f.reads() > 0, "the station checked the latest chain rather than trusting the device's old one");
  c.conn.close(0, "done");
});

test("a station admits a long personal chain without putting it in the hello line", async (t) => {
  const f = await fixture(t, 63);
  assert.equal(f.person.length, 65);
  const c = await f.open(f.bBase);
  assert.equal(c.answer.ok, true);
  assert.ok(f.reads() > 0);
  c.conn.close(0, "done");
});

test("a station admits the longest personal chain the cloud accepts", async (t) => {
  const f = await fixture(t, 1022);
  assert.equal(f.person.length, 1024);
  let last = performance.now(), longest = 0;
  const tick = setInterval(() => { const now = performance.now(); longest = Math.max(longest, now - last); last = now; }, 1);
  const start = performance.now();
  try {
    const c = await f.open(f.bBase);
    assert.equal(c.answer.ok, true);
    await new Promise<void>((resolve) => setImmediate(resolve));
    if (process.env.MEASURE_PERSON_LOCK) console.log(`PERSON_1024_HANDSHAKE_MS ${(performance.now() - start).toFixed(1)} EVENT_LOOP_GAP_MS ${longest.toFixed(1)}`);
    c.conn.close(0, "done");
  } finally {
    clearInterval(tick);
  }
});

test("a live connection closes when its personal device is removed or updates go offline", async (t) => {
  const f = await fixture(t);
  const a = await f.open(f.aBase, f.person);
  assert.equal(a.answer.ok, true);
  f.append(f.b, "device.remove", { key: f.a.id });
  f.setLatest([...f.person]);
  const update = f.tell();
  assert.equal(await a.conn.closed(), "lock_unconfirmed", "a pending update closes the connection before validation finishes");
  await update;
  const b = await f.open(f.bBase);
  assert.equal(b.answer.ok, true);
  f.cloud.setPersonalOnline(false);
  assert.equal(await b.conn.closed(), "lock_unconfirmed");
  const offline = await f.open(f.bBase);
  assert.equal(offline.answer.code, "lock_unconfirmed");
  offline.conn.close(0, "done");
});

test("a device still named by the workspace keeps that admission until the workspace also removes it", async (t) => {
  const f = await fixture(t, 0, true);
  const a = await f.open(f.aBase);
  assert.equal(a.answer.ok, true);
  f.append(f.b, "device.remove", { key: f.a.id });
  f.setLatest([...f.person]);
  await f.tell();
  const request = await a.conn.openBi();
  await line(request, { method: "GET", path: "/not-admin" });
  assert.equal((await new Reader(request).line()).status, 404, "the workspace device path is still in force");
  a.conn.close(0, "done");
});

test("a new personal genesis closes old connections and an out-of-order snapshot cannot restore it", async (t) => {
  const f = await fixture(t), old = [...f.person];
  const c = await f.open(f.aBase, old);
  assert.equal(c.answer.ok, true);
  const replacement = key(), replacementBase = key();
  const anew = entry(replacement, `person:${SUB}`, 0, null, "genesis", { sub: SUB, device: { key: replacement.id, id: replacementBase.hex, label: "new" } });
  f.setLatest([anew]);
  await f.tell();
  assert.equal(await c.conn.closed(), "lock_unconfirmed");
  await f.cloud.takePersonal(SUB, old, 1);
  assert.equal(f.cloud.personalHead(SUB)?.genesis, entryHash(anew));
  const stale = await f.open(f.aBase, old);
  assert.equal(stale.answer.code, "lock_unconfirmed");
  stale.conn.close(0, "done");
});

test("after restart a stale cloud prefix and a repeated version cannot undo a kept revocation", async (t) => {
  const f = await fixture(t), old = [...f.person];
  f.append(f.b, "device.remove", { key: f.a.id });
  f.setLatest([...f.person]);
  const removed = await f.open(f.aBase);
  assert.equal(removed.answer.code, "lock_unconfirmed");
  removed.conn.close(0, "done");
  f.restart();
  f.setLatest(old); // The cloud has lost the tail, but reports a new snapshot version.
  const stale = await f.open(f.aBase, old);
  assert.equal(stale.answer.code, "lock_unconfirmed");
  stale.conn.close(0, "done");
  assert.equal(f.cloud.personalHead(SUB)?.head, entryHash(old.at(-1)!), "the cloud version describes the shorter snapshot");
  await f.tell(); // Repeating that same version must not replace the verified chain on disk either.
  const repeated = await f.open(f.aBase, old);
  assert.equal(repeated.answer.code, "lock_unconfirmed");
  repeated.conn.close(0, "done");
  const remaining = await f.open(f.bBase, old);
  assert.equal(remaining.answer.ok, true, "the remaining device is judged by the longer kept chain");
  remaining.conn.close(0, "done");
});

test("a revocation from another station during verification cannot admit a device", async (t) => {
  const f = await fixture(t);
  const verifier = f.cloud.personVerifier();
  const admit = verifier.admit.bind(verifier);
  let release!: () => void, reached!: () => void;
  const paused = new Promise<void>((resolve) => { release = resolve; });
  const checking = new Promise<void>((resolve) => { reached = resolve; });
  verifier.admit = async (...args) => {
    const role = await admit(...args);
    reached();
    await paused;
    return role;
  };
  const opening = f.open(f.aBase);
  try {
    await checking;
    f.append(f.b, "device.remove", { key: f.a.id });
    const other = new PersonChains(f.data);
    try { other.keep(entryHash(f.person[0]!), [...f.person]); } finally { other.close(); }
  } finally { release(); }
  const refused = await opening;
  assert.equal(refused.answer.code, "lock_unconfirmed", "the chain changed after the worker checked it");
  refused.conn.close(0, "done");
  verifier.admit = admit;
  const stale = await f.open(f.aBase);
  assert.equal(stale.answer.code, "lock_unconfirmed", "the other process's longer chain is used even with an old cloud snapshot");
  stale.conn.close(0, "done");
});

test("an update arriving while a device is being checked cannot admit a removed device", async (t) => {
  const f = await fixture(t);
  const verifier = f.cloud.personVerifier();
  const admit = verifier.admit.bind(verifier);
  let release!: () => void, reached!: () => void;
  const paused = new Promise<void>((resolve) => { release = resolve; });
  const checking = new Promise<void>((resolve) => { reached = resolve; });
  verifier.admit = async (...args) => {
    const role = await admit(...args);
    reached();
    await paused;
    return role;
  };
  const opening = f.open(f.aBase);
  try {
    await checking;
    f.append(f.b, "device.remove", { key: f.a.id });
    f.setLatest([...f.person]);
    await f.tell();
  } finally { release(); }
  const refused = await opening;
  assert.equal(refused.answer.code, "lock_unconfirmed");
  refused.conn.close(0, "done");
});
