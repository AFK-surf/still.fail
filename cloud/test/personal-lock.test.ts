// A person's own lock as the cloud keeps it (src/personal-lock.ts, docs/personal-lock.md): each entry following the last
// and signed by a device on it; a chain begun anew is taken (all of a person's devices lost), and devices decide whether
// to follow it. Hashes and signatures are the stations' and the core's.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import { admitPerson, apply, endpointBytes, entryHash, genesis, LockRefusal, personFold, signedBytes, type Entry } from "../../station/src/cloud/lock.ts";
import { extendPersonal, type PersonalEntry, type PersonalBody } from "../src/personal-lock.ts";
import { harness } from "./harness.ts";

const SUB = "s1";

function key() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  return { id: `ed25519:${raw.toString("hex")}`, privateKey };
}

function entry(by: ReturnType<typeof key>, seq: number, prev: string | null, kind: string, body: unknown, ws = `person:${SUB}`): PersonalEntry {
  const e = { v: 1 as const, ws, seq, prev, at: 1, kind, body: body as PersonalBody };
  const hash = entryHash(e as unknown as Entry);
  return { ...e, sig: { key: by.id, alg: "Ed25519", sig: sign(null, signedBytes(hash), by.privateKey).toString("hex") } };
}
const hashOf = (e: PersonalEntry) => entryHash(e as unknown as Entry);
const device = (k: ReturnType<typeof key>) => ({ key: k.id, id: k.id.slice(8), label: "x" });

test("a lock begins with its device's own genesis, and grows only by a device on it", () => {
  const a = key(), b = key(), stranger = key();
  const first = entry(a, 0, null, "genesis", { sub: SUB, device: device(a) });
  const kept = extendPersonal(SUB, [], [first]);
  const added = entry(a, 1, hashOf(first), "device", device(b));
  const two = extendPersonal(SUB, kept, [added]);
  assert.equal(two.length, 2);
  assert.deepEqual(personFold(two, SUB).devices.map((d) => d.key).sort(), [a.id, b.id].sort());
  // A device not on it, a stolen login's.
  assert.throws(() => extendPersonal(SUB, two, [entry(stranger, 2, hashOf(added), "device", device(stranger))]), /lock_refused/);
  // Not following what is kept.
  assert.throws(() => extendPersonal(SUB, two, [entry(a, 2, "00", "device", device(stranger))]), /lock_refused/);
  // Another person's.
  assert.throws(() => extendPersonal("s2", [], [first]), /lock_refused/);
  // A genesis signed by another than the device it names.
  assert.throws(() => extendPersonal(SUB, [], [entry(stranger, 0, null, "genesis", { sub: SUB, device: device(a) })]), /lock_refused/);
  // Signature not its own.
  const forged = { ...added, body: device(stranger) };
  assert.throws(() => extendPersonal(SUB, kept, [forged]), /lock_refused/);
});

test("the last device is not removed; one taken off signs no more; a lock may begin anew", () => {
  const a = key(), b = key(), c = key();
  const first = entry(a, 0, null, "genesis", { sub: SUB, device: device(a) });
  assert.throws(() => extendPersonal(SUB, [first], [entry(a, 1, hashOf(first), "device.remove", { key: a.id })]), /lock_refused/);
  const added = entry(a, 1, hashOf(first), "device", device(b));
  const gone = entry(b, 2, hashOf(added), "device.remove", { key: a.id });
  const kept = extendPersonal(SUB, [first, added], [gone]);
  assert.throws(() => extendPersonal(SUB, kept, [entry(a, 3, hashOf(gone), "device", device(c))]), /lock_refused/);
  const anew = extendPersonal(SUB, kept, [entry(c, 0, null, "genesis", { sub: SUB, device: device(c) })]);
  assert.equal(anew.length, 1);
});

test("what is not an entry is refused", () => {
  assert.throws(() => extendPersonal(SUB, [], []), /invalid_lock_entries/);
  assert.throws(() => extendPersonal(SUB, [], [{ v: 2 }]), /invalid_lock_entries/);
  assert.throws(() => extendPersonal(SUB, [], [{ v: 2, seq: 0 }]), /lock_refused/);
  assert.throws(() => extendPersonal(SUB, [], "x"), /invalid_lock_entries/);
});

test("a full personal chain can be kept even when it exceeds one storage value", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), sub = tokens.subject, ws = `person:${sub}`;
    const signer = key(), chain: PersonalEntry[] = [];
    chain.push(entry(signer, 0, null, "genesis", { sub, device: device(signer) }, ws));
    for (let i = 1; i < 1024; i++) {
      chain.push(entry(signer, i, hashOf(chain.at(-1)!), "device", { ...device(signer), label: `${i}${"x".repeat(3000)}` }, ws));
    }
    assert.ok(Buffer.byteLength(JSON.stringify(chain)) > 2_000_000);
    const accounts: any = await h.mf.getDurableObjectNamespace("ACCOUNTS", "api");
    const account = accounts.get(accounts.idFromName(sub));
    const saved = await account.appendPersonalLock(sub, chain);
    assert.equal(saved.refused, null);
    // The local Cloudflare emulator permits an oversized KV value; production limits key plus value to 2 MB.
    const sizes = await account.personalValueSizes() as { key: string; bytes: number }[];
    assert.ok(sizes.every(({ bytes }) => bytes < 1_000_000), `individual storage values must fit the provider's limit: ${JSON.stringify(sizes)}`);
    const fetched = await (await h.as(tokens)("GET", "/v1/me/personal-lock")).json() as { entries: PersonalEntry[] };
    assert.deepEqual(fetched.entries, chain);
    const replacement = key(), first = entry(replacement, 0, null, "genesis", { sub, device: device(replacement) }, ws);
    assert.equal((await account.appendPersonalLock(sub, [first])).refused, null);
    const afterReset = await account.personalValueSizes() as { key: string; bytes: number }[];
    assert.equal(afterReset.filter(({ key }) => key.startsWith("personal-lock-part:")).length, 1, "reset discards old parts atomically");
    assert.deepEqual((await (await h.as(tokens)("GET", "/v1/me/personal-lock")).json() as { entries: PersonalEntry[] }).entries, [first]);
  } finally { await h.close(); }
});

test("a personal lock kept by an older cloud is read and migrated on its next extension", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), sub = tokens.subject, ws = `person:${sub}`, alice = h.as(tokens);
    const a = key(), b = key(), first = entry(a, 0, null, "genesis", { sub, device: device(a) }, ws);
    const accounts: any = await h.mf.getDurableObjectNamespace("ACCOUNTS", "api");
    const account = accounts.get(accounts.idFromName(sub));
    await account.keepLegacyPersonal([first]);
    assert.deepEqual((await (await alice("GET", "/v1/me/personal-lock")).json() as { entries: PersonalEntry[] }).entries, [first]);
    const added = entry(a, 1, hashOf(first), "device", device(b), ws);
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [added] })).status, 200);
    assert.deepEqual((await (await alice("GET", "/v1/me/personal-lock")).json() as { entries: PersonalEntry[] }).entries, [first, added]);
    const sizes = await account.personalValueSizes() as { key: string }[];
    assert.equal(sizes.some(({ key }) => key === "personal-lock"), false);
    assert.equal(sizes.some(({ key }) => key === "personal-lock-part:0"), true);
  } finally { await h.close(); }
});

test("guarded restore accepts a bounded batch including a valid multibyte entry", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), alice = h.as(tokens), sub = tokens.subject, ws = `person:${sub}`;
    const a = key(), b = key(), first = entry(a, 0, null, "genesis", { sub, device: device(a) }, ws);
    const path = "/v1/me/personal-lock", restore = `${path}/append`;
    assert.equal((await alice("POST", path, { entries: [first] })).status, 200);
    const added = entry(a, 1, hashOf(first), "device", { ...device(b), label: "长".repeat(3000) }, ws);
    const payload = { entries: [added], expect: { length: 1, head: hashOf(first) } };
    assert.ok(JSON.stringify(added).length < 4096 && Buffer.byteLength(JSON.stringify(payload)) > 8192);
    assert.equal((await alice("POST", path, payload)).status, 400, "the ordinary endpoint retains its smaller request limit");
    assert.equal((await alice("POST", restore, payload)).status, 200);
    assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, [first, added]);
    assert.equal((await alice("POST", restore, { ...payload, extra: "x".repeat(256 * 1024) })).status, 400, "restore requests remain bounded");
  } finally { await h.close(); }
});

test("the personal lock API requires its account, keeps each account's chain separate and rejects another's entry", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const bob = h.as(await h.login("bob"));
    const path = "/v1/me/personal-lock";
    assert.equal((await h.fetch(path)).status, 401);
    assert.deepEqual(await (await alice("GET", path)).json(), { entries: [] });
    assert.deepEqual(await (await bob("GET", path)).json(), { entries: [] });

    const signer = key();
    const first = entry(signer, 0, null, "genesis", { sub: aliceTokens.subject, device: device(signer) }, `person:${aliceTokens.subject}`);
    assert.equal((await alice("POST", path, { entries: [first] })).status, 200);
    assert.deepEqual(await (await alice("GET", path)).json(), { entries: [first] });
    assert.deepEqual(await (await bob("GET", path)).json(), { entries: [] });
    assert.equal((await bob("POST", path, { entries: [first] })).status, 409);

    const stranger = key();
    const forged = entry(stranger, 1, hashOf(first), "device", device(stranger), `person:${aliceTokens.subject}`);
    assert.equal((await alice("POST", path, { entries: [forged] })).status, 409);
    assert.deepEqual(await (await alice("GET", path)).json(), { entries: [first] });
  } finally {
    await h.close();
  }
});

test("a removed device cannot replace the cloud's longer chain with a fork or an old prefix", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const alice = h.as(tokens);
    const path = "/v1/me/personal-lock", sub = tokens.subject, personWs = `person:${sub}`;
    const a = key(), b = key(), c = key(), cBase = key();
    const first = entry(a, 0, null, "genesis", { sub, device: device(a) }, personWs);
    const added = entry(a, 1, hashOf(first), "device", device(b), personWs);
    const removed = entry(b, 2, hashOf(added), "device.remove", { key: a.id }, personWs);
    const kept = [first, added, removed];
    for (const e of kept) assert.equal((await alice("POST", path, { entries: [e] })).status, 200);

    // A station with this personal genesis pinned, but no personal chain in memory yet (as after restart).
    const ws = "01HZZZZZZZZZZZZZZZZZZZZZZZ", signer = key(), ownerBase = key();
    const owner = { id: ownerBase.id.slice(8), sub, kind: "app", label: "owner", sign_key: signer.id };
    const workspaceFirst = entry(signer, 0, null, "genesis", {
      owner: sub, origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
      members: [{ sub, email: "a@x", role: "owner" }], devices: [owner], passkeys: [], stations: [], gateways: [],
    }, ws);
    const workspace = genesis(workspaceFirst as unknown as Entry);
    const bind = entry(signer, 1, hashOf(workspaceFirst), "person", { sub, person: hashOf(first) }, ws);
    const bound = apply(workspace, bind as unknown as Entry, 2000);
    const endpoint = "ee".repeat(32);
    const who = { sub, endpoint, base: cBase.id.slice(8), proof: sign(null, endpointBytes(ws, endpoint), cBase.privateKey).toString("hex") };
    assert.throws(() => admitPerson(bound, who, kept), LockRefusal);

    const fork = entry(a, 2, hashOf(added), "device", { ...device(c), id: who.base }, personWs);
    const response = await alice("POST", path, { entries: [fork] });
    const said = await (await alice("GET", path)).json() as { entries: PersonalEntry[] };
    // This is the same rule the station's verifier applies to a fetched chain. Transport and restart are tested in station.
    assert.throws(() => admitPerson(bound, who, said.entries), LockRefusal,
      "a station with no cached personal chain must not admit the fork's device from the cloud");
    assert.equal(response.status, 409);
    assert.deepEqual(said.entries, kept);

    // A complete earlier chain, or an overlapping suffix, is a harmless retry and never shortens what was kept.
    for (const replay of [[first, added], [added]]) {
      assert.equal((await alice("POST", path, { entries: replay })).status, 200);
      assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, kept);
    }
    assert.equal((await alice("POST", path, { entries: [first, added, fork] })).status, 409);
    assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, kept);
  } finally {
    await h.close();
  }
});

test("concurrent appends cannot both take the same place, and a recovery cannot resurrect an old genesis", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), alice = h.as(tokens);
    const path = "/v1/me/personal-lock", sub = tokens.subject, ws = `person:${sub}`;
    const a = key(), b = key(), c = key(), recovery = key();
    const first = entry(a, 0, null, "genesis", { sub, device: device(a) }, ws);
    assert.equal((await alice("POST", path, { entries: [first] })).status, 200);
    const left = entry(a, 1, hashOf(first), "device", device(b), ws);
    const right = entry(a, 1, hashOf(first), "device", device(c), ws);
    const results = await Promise.all([alice("POST", path, { entries: [left] }), alice("POST", path, { entries: [right] })]);
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    const before = (await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries;
    assert.equal(before.length, 2);
    assert.ok(hashOf(before[1]!) === hashOf(left) || hashOf(before[1]!) === hashOf(right));

    const anew = entry(recovery, 0, null, "genesis", { sub, device: device(recovery) }, ws);
    assert.equal((await alice("POST", path, { entries: [anew] })).status, 200, "a distinct genesis still permits recovery");
    assert.equal((await alice("POST", path, { entries: [anew] })).status, 200, "retrying the new genesis is safe");
    assert.equal((await alice("POST", path, { entries: before })).status, 409, "a retired genesis cannot be brought back as another recovery");
    assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, [anew]);
  } finally {
    await h.close();
  }
});

test("a restore does not replace a different lock created after its empty read", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), alice = h.as(tokens);
    const path = "/v1/me/personal-lock", restore = `${path}/append`, sub = tokens.subject, ws = `person:${sub}`;
    const a = key(), b = key();
    const newLock = entry(a, 0, null, "genesis", { sub, device: device(a) }, ws);
    const oldLock = entry(b, 0, null, "genesis", { sub, device: device(b) }, ws);
    assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, []);
    assert.equal((await alice("POST", path, { entries: [newLock] })).status, 200);
    assert.equal((await alice("POST", restore, { entries: [oldLock], expect: { length: 0, head: null } })).status, 409);
    assert.deepEqual((await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries, [newLock]);
    const added = entry(a, 1, hashOf(newLock), "device", device(b), ws);
    assert.equal((await alice("POST", restore, { entries: [added] })).status, 400, "the guarded route requires an expected head");
    assert.equal((await alice("POST", restore, { entries: [added], expect: { length: 1, head: hashOf(newLock) } })).status, 200);
  } finally {
    await h.close();
  }
});

test("two guarded first locks cannot replace one another", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice"), alice = h.as(tokens);
    const path = "/v1/me/personal-lock", guarded = `${path}/append`, sub = tokens.subject, ws = `person:${sub}`;
    const a = key(), b = key();
    const first = entry(a, 0, null, "genesis", { sub, device: device(a) }, ws);
    const second = entry(b, 0, null, "genesis", { sub, device: device(b) }, ws);
    const expect = { length: 0, head: null };
    const results = await Promise.all([
      alice("POST", guarded, { entries: [first], expect }),
      alice("POST", guarded, { entries: [second], expect }),
    ]);
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    const saved = (await (await alice("GET", path)).json() as { entries: PersonalEntry[] }).entries;
    assert.equal(saved.length, 1);
    assert.ok(hashOf(saved[0]!) === hashOf(first) || hashOf(saved[0]!) === hashOf(second));
  } finally { await h.close(); }
});

test("an enrolled station reads only the current personal locks of its workspace's members", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice"), alice = h.as(aliceTokens);
    const bobTokens = await h.login("bob"), bob = h.as(bobTokens);
    const a = key(), b = key(), station = key(), outsider = key();
    const first = entry(a, 0, null, "genesis", { sub: aliceTokens.subject, device: device(a) }, `person:${aliceTokens.subject}`);
    const bobFirst = entry(b, 0, null, "genesis", { sub: bobTokens.subject, device: device(b) }, `person:${bobTokens.subject}`);
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [first] })).status, 200);
    assert.equal((await bob("POST", "/v1/me/personal-lock", { entries: [bobFirst] })).status, 200);
    const home = await (await alice("POST", "/v1/workspaces", { name: "Home" })).json() as { id: string };
    const elsewhere = await (await bob("POST", "/v1/workspaces", { name: "Elsewhere" })).json() as { id: string };
    const enrollment = await (await alice("POST", `/v1/workspaces/${home.id}/enrollments`, { name: "test" })).json() as { token: string };
    const id = station.id.slice(8);
    const proof = sign(null, Buffer.from(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${id}`), station.privateKey).toString("hex");
    assert.equal((await h.fetch("/v1/stations/enroll", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: enrollment.token, station: id, signature: proof }) })).status, 200);
    const ts = h.now();
    const connectProof = sign(null, Buffer.from(`stillfail-station-connect-v1:${h.origin}:${id}:${ts}`), station.privateKey).toString("hex");
    const socket = (await h.fetch("/v1/stations/connect", { headers: { upgrade: "websocket", "x-stillfail-station": id, "x-stillfail-ts": String(ts), "x-stillfail-signature": connectProof } })).webSocket!;
    const frames: any[] = [];
    let waiting: ((f: any) => void) | null = null;
    socket.addEventListener("message", (event) => {
      const value = event.data === "pong" ? "pong" : JSON.parse(event.data as string);
      if (waiting) { const take = waiting; waiting = null; take(value); }
      else frames.push(value);
    });
    socket.accept();
    const next = () => frames.length ? Promise.resolve(frames.shift()) : new Promise<any>((resolve) => { waiting = resolve; });
    assert.equal((await next()).type, "state");
    const ask = (by: ReturnType<typeof key>, workspace: string, sub: string, signedBody?: string) => {
      const body = JSON.stringify({ workspace, sub }), ts = h.now(), stationId = by.id.slice(8);
      const digest = createHash("sha256").update(signedBody ?? body).digest("hex");
      const signature = sign(null, Buffer.from(`stillfail-station-personal-lock-v1:${h.origin}:${stationId}:${ts}:${digest}`), by.privateKey).toString("hex");
      return h.fetch("/v1/stations/personal-lock", { method: "POST", headers: { "content-type": "application/json", "x-stillfail-station": stationId, "x-stillfail-ts": String(ts), "x-stillfail-signature": signature }, body });
    };
    const found = await ask(station, home.id, aliceTokens.subject);
    assert.equal(found.status, 200);
    assert.deepEqual(await found.json(), { entries: [first], version: 1 });
    assert.equal((await ask(outsider, home.id, aliceTokens.subject)).status, 401);
    assert.equal((await ask(station, elsewhere.id, bobTokens.subject)).status, 403);
    assert.equal((await ask(station, home.id, bobTokens.subject)).status, 403);
    assert.equal((await ask(station, home.id, aliceTokens.subject, "{}" )).status, 401, "the signature covers the requested person and workspace");
    const added = entry(a, 1, hashOf(first), "device", device(key()), `person:${aliceTokens.subject}`);
    assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [added] })).status, 200);
    socket.send("ping");
    const seen: any[] = [];
    for (;;) { const frame = await next(); if (frame === "pong") break; seen.push(frame); }
    assert.deepEqual(seen.find((f) => f.type === "personal.lock"), { type: "personal.lock", sub: aliceTokens.subject, entries: [first, added], version: 2 });

    // The HTTP worker may stop after the account committed but before it could notify the directory.
    const accounts: any = await h.mf.getDurableObjectNamespace("ACCOUNTS", "api");
    const account = accounts.get(accounts.idFromName(aliceTokens.subject));
    const afterInterrupted = entry(a, 2, hashOf(added), "device", device(key()), `person:${aliceTokens.subject}`);
    await account.appendPersonalLock(aliceTokens.subject, [afterInterrupted]);
    assert.equal(await account.personalPending(), true);
    assert.notEqual(await account.nextAccountAlarm(), null, "a retry was scheduled before the commit");
    await account.personalDelivered(2);
    assert.equal(await account.personalPending(), true, "acknowledging an older revision keeps the newer one pending");
    await account.fireAccountAlarm();
    assert.equal(await account.personalPending(), false);
    socket.send("ping");
    const retried: any[] = [];
    for (;;) { const frame = await next(); if (frame === "pong") break; retried.push(frame); }
    assert.deepEqual(retried.find((f) => f.type === "personal.lock"), { type: "personal.lock", sub: aliceTokens.subject, entries: [first, added, afterInterrupted], version: 3 }, "the pending change is delivered after the interrupted request");
    socket.close();
    const chain = [first, added, afterInterrupted];
    for (let i = 0; i < 62; i++) {
      const more = entry(a, chain.length, hashOf(chain.at(-1)!), "device", { ...device(a), label: `a${i}` }, `person:${aliceTokens.subject}`);
      assert.equal((await alice("POST", "/v1/me/personal-lock", { entries: [more] })).status, 200);
      chain.push(more);
    }
    assert.equal(chain.length, 65);
    assert.deepEqual((await (await ask(station, home.id, aliceTokens.subject)).json() as { entries: PersonalEntry[] }).entries, chain);
  } finally {
    await h.close();
  }
});
