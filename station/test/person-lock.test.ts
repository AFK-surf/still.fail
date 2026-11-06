// A person's own lock in a workspace's (rules/src/lock/person.mbt, docs/personal-lock.md): only a member's own device
// binds a lock to them, a chain holds only as signed by a device on it, and a device is let in on it only as the
// lock bound there says, not on one taken off since, nor on another lock.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { once } from "node:events";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { type Entry, LockRefusal, admit, admitPerson, apply, endpointBytes, entryHash, genesis, personFold, signedBytes } from "../src/cloud/lock.ts";
import { PersonChains } from "../src/mesh/person-chains.ts";

const WS = "w1";

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } } as Entry);
const next = (s: { seq: number; head: string }, kind: string, body: unknown): Omit<Entry, "sig"> => ({ v: 1, ws: WS, seq: s.seq + 1, prev: s.head, at: 1000, kind, body });

/// A workspace: owner alice, admin bob, member carol, each with a device that signs.
function workspace() {
  const p = (sub: string) => ({ sub, signer: ed(), base: ed() });
  const alice = p("alice"), bob = p("bob"), carol = p("carol");
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }, { sub: "bob", email: "b@x", role: "admin" }, { sub: "carol", email: "c@x", role: "member" }],
    devices: [alice, bob, carol].map((d) => ({ id: d.base.hex, sub: d.sub, kind: "app", label: d.sub, sign_key: d.signer.id })),
    passkeys: [], stations: [], gateways: [],
  };
  return { alice, bob, carol, state: genesis(signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body }, alice.signer)) };
}

/// A person's lock: `chain`, entries of it as made so far.
function personal(sub: string) {
  const first = { key: ed(), base: ed() };
  const chain: Entry[] = [];
  const add = (kind: string, body: unknown, by: Key) => {
    const last = chain[chain.length - 1];
    chain.push(signed({ v: 1, ws: `person:${sub}`, seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body }, by));
  };
  add("genesis", { sub, device: { key: first.key.id, id: first.base.hex, label: "first" } }, first.key);
  return { first, chain, add };
}

const who = (sub: string, base: Key, endpoint = "ee".repeat(32)) => ({ sub, endpoint, base: base.hex, proof: base.sign(endpointBytes(WS, endpoint)) });
const genesisOf = (chain: Entry[]) => entryHash(chain[0]!);

test("only a member's own device binds them to a lock", () => {
  const w = workspace();
  const lock = personal("carol");
  const bind = (sub: string) => ({ sub, person: genesisOf(lock.chain) });
  // Their own.
  const bound = apply(w.state, signed(next(w.state, "person", bind("carol")), w.carol.signer), 2000);
  assert.equal(bound.persons.get("carol"), genesisOf(lock.chain));
  // Another member's, or an admin's, or the owner's: no one binds someone else.
  assert.throws(() => apply(w.state, signed(next(w.state, "person", bind("alice")), w.carol.signer), 2000), /bind only themselves/);
  assert.throws(() => apply(w.state, signed(next(w.state, "person", bind("carol")), w.bob.signer), 2000), /bind only themselves/);
  assert.throws(() => apply(w.state, signed(next(w.state, "person", bind("carol")), w.alice.signer), 2000), /bind only themselves/);
  // A device an admin put in under carol's name is not her own: stays in the chain, and binds no one.
  const planted = ed(), plantedBase = ed();
  const withPlanted = apply(w.state, signed(next(w.state, "device", { id: plantedBase.hex, sub: "carol", kind: "app", label: "x", sign_key: planted.id }), w.bob.signer), 2000);
  assert.throws(() => apply(withPlanted, signed(next(withPlanted, "person", bind("carol")), planted), 2000), /bind only themselves/);
  // Not a lock's name, not a member.
  assert.throws(() => apply(w.state, signed(next(w.state, "person", { sub: "carol", person: "nope" }), w.carol.signer), 2000), /genesis's hash/);
  assert.throws(() => apply(w.state, signed(next(w.state, "person", { sub: "dan", person: genesisOf(lock.chain) }), w.carol.signer), 2000), /member's/);
  // Taken out of the workspace, the binding goes too.
  const removed = apply(bound, signed(next(bound, "member.remove", { sub: "carol" }), w.alice.signer), 2000);
  assert.equal(removed.persons.has("carol"), false);
});

test("a chain holds only as signed by a device on it", () => {
  const lock = personal("carol");
  const second = { key: ed(), base: ed() };
  lock.add("device", { key: second.key.id, id: second.base.hex, label: "second" }, lock.first.key);
  assert.deepEqual(personFold(lock.chain, "carol").devices.map((d) => d.label).sort(), ["first", "second"]);
  assert.throws(() => personFold(lock.chain, "alice"), /another lock/);
  assert.throws(() => personFold(lock.chain.slice(1), "carol"), /genesis|follow/);
  const stranger = ed();
  const forged = personal("carol");
  forged.add("device", { key: stranger.id, id: ed().hex, label: "x" }, stranger);
  assert.throws(() => personFold(forged.chain, "carol"), /not signed by a device/);
  const lastGoes = personal("carol");
  lastGoes.add("device.remove", { key: lastGoes.first.key.id }, lastGoes.first.key);
  assert.throws(() => personFold(lastGoes.chain, "carol"), /its last/);
  const changed = [...lock.chain];
  changed[1] = { ...changed[1]!, body: { key: stranger.id, id: second.base.hex, label: "x" } };
  assert.throws(() => personFold(changed, "carol"), /signature invalid|follow/);
});

test("a device is let in on the lock its member bound, and no other way", () => {
  const w = workspace();
  const lock = personal("carol");
  const second = { key: ed(), base: ed() };
  lock.add("device", { key: second.key.id, id: second.base.hex, label: "second" }, lock.first.key);
  const bound = apply(w.state, signed(next(w.state, "person", { sub: "carol", person: genesisOf(lock.chain) }), w.carol.signer), 2000);

  // Not a device of the workspace's lock: it says so, and the personal lock lets it in, with the member's role.
  assert.throws(() => admit(bound, who("carol", second.base), 2000), LockRefusal);
  const admitted = admitPerson(bound, who("carol", second.base), lock.chain);
  assert.deepEqual([admitted.device, admitted.role], [second.base.hex, "member"]);

  // Not bound.
  assert.throws(() => admitPerson(w.state, who("carol", second.base), lock.chain), LockRefusal);
  // Someone else's account.
  assert.throws(() => admitPerson(bound, who("bob", second.base), lock.chain), LockRefusal);
  // A device not on it.
  const other = ed();
  assert.throws(() => admitPerson(bound, who("carol", other), lock.chain), LockRefusal);
  // Its base key's proof for another endpoint.
  assert.throws(() => admitPerson(bound, { ...who("carol", second.base), endpoint: "aa".repeat(32) }, lock.chain), LockRefusal);
  // A lock of the attacker's own, all in order but not the one bound.
  const theirs = personal("carol");
  assert.throws(() => admitPerson(bound, who("carol", theirs.first.base), theirs.chain), LockRefusal);
  // Taken off the lock.
  const before = [...lock.chain];
  lock.add("device.remove", { key: second.key.id }, lock.first.key);
  assert.throws(() => admitPerson(bound, who("carol", second.base), lock.chain), LockRefusal);
  // ...though the chain from before still reads as it did: the station goes by the longest it heard.
  const kept = new PersonChains();
  const pin = genesisOf(lock.chain);
  kept.keep(pin, lock.chain);
  const judged = kept.newest(pin, "carol", before);
  assert.equal(judged.length, lock.chain.length);
  assert.throws(() => admitPerson(bound, who("carol", second.base), judged), LockRefusal);
  // A chain at odds with the one kept.
  const fork = [...before];
  const third = { key: ed() };
  const last = fork[fork.length - 1]!;
  fork.push(signed({ v: 1, ws: "person:carol", seq: fork.length, prev: entryHash(last), at: 1000, kind: "device", body: { key: third.key.id, id: ed().hex, label: "x" } }, lock.first.key));
  assert.throws(() => kept.newest(pin, "carol", fork), LockRefusal);
});

test("removing a device revokes its base even if another signing key reused that base", () => {
  const w = workspace();
  const lock = personal("carol"), secondKey = ed(), otherKey = ed(), otherBase = ed();
  const bound = apply(w.state, signed(next(w.state, "person", { sub: "carol", person: genesisOf(lock.chain) }), w.carol.signer), 2000);
  lock.add("device", { key: secondKey.id, id: lock.first.base.hex, label: "same base" }, lock.first.key);
  lock.add("device", { key: otherKey.id, id: otherBase.hex, label: "another device" }, lock.first.key);
  lock.add("device.remove", { key: lock.first.key.id }, otherKey);
  assert.throws(() => admitPerson(bound, who("carol", lock.first.base), lock.chain), LockRefusal,
    "the removed device's base must not still admit it through another signing key");
  assert.equal(admitPerson(bound, who("carol", otherBase), lock.chain).device, otherBase.hex);
  assert.deepEqual(personFold(lock.chain, "carol").devices.map((d) => d.key), [otherKey.id]);
  lock.add("device", { key: ed().id, id: ed().hex, label: "forged" }, secondKey);
  assert.throws(() => personFold(lock.chain, "carol"), /not signed by a device/);
});

test("removing the last physical device with aliased keys leaves the lock needing recovery", () => {
  const w = workspace(), lock = personal("carol"), alias = ed();
  const bound = apply(w.state, signed(next(w.state, "person", { sub: "carol", person: genesisOf(lock.chain) }), w.carol.signer), 2000);
  lock.add("device", { key: alias.id, id: lock.first.base.hex, label: "same base" }, lock.first.key);
  lock.add("device.remove", { key: lock.first.key.id }, alias);
  assert.deepEqual(personFold(lock.chain, "carol").devices, []);
  assert.throws(() => admitPerson(bound, who("carol", lock.first.base), lock.chain), LockRefusal);
  lock.add("device", { key: ed().id, id: ed().hex, label: "forged" }, alias);
  assert.throws(() => personFold(lock.chain, "carol"), /not signed by a device/);
});

test("a manager can bind a new member through a first device they themselves approved", () => {
  const w = workspace(), fake = { signer: ed(), base: ed() }, dave = personal("dave");
  let state = apply(w.state, signed(next(w.state, "member", { sub: "dave", email: "d@x", role: "member" }), w.alice.signer), 2000);
  state = apply(state, signed(next(state, "device", { id: fake.base.hex, sub: "dave", kind: "app", label: "first", sign_key: fake.signer.id }), w.bob.signer), 2000);
  state = apply(state, signed(next(state, "person", { sub: "dave", person: genesisOf(dave.chain) }), fake.signer), 2000);
  assert.equal(state.persons.get("dave"), genesisOf(dave.chain), "first-device ownership depends on the manager's prior approval");
});

test("a station remembers a personal revocation across restart and overlapping processes", () => {
  const w = workspace(), lock = personal("carol"), second = { key: ed(), base: ed() };
  lock.add("device", { key: second.key.id, id: second.base.hex, label: "second" }, lock.first.key);
  const old = [...lock.chain], pin = genesisOf(old);
  const bound = apply(w.state, signed(next(w.state, "person", { sub: "carol", person: pin }), w.carol.signer), 2000);
  const data = mkdtempSync(join(tmpdir(), "person-chains-"));
  const before = new PersonChains(data), overlap = new PersonChains(data);
  before.keep(pin, old);
  lock.add("device.remove", { key: lock.first.key.id }, second.key);
  before.keep(pin, lock.chain);
  // A process started during handover must not overwrite a newer chain with its old snapshot.
  assert.equal(overlap.keep(pin, old).length, lock.chain.length);
  before.close();
  overlap.close();
  const restarted = new PersonChains(data);
  const judged = restarted.newest(pin, "carol", old);
  assert.equal(judged.length, lock.chain.length);
  assert.throws(() => admitPerson(bound, who("carol", lock.first.base), judged), LockRefusal);
  assert.equal(admitPerson(bound, who("carol", second.base), judged).device, second.base.hex);
  restarted.close();
});

test("a competing writer is refused without waiting and a killed writer cannot replace the stored chain", async () => {
  const lock = personal("carol"), second = { key: ed(), base: ed() };
  lock.add("device", { key: second.key.id, id: second.base.hex, label: "second" }, lock.first.key);
  const old = [...lock.chain], pin = genesisOf(old);
  const data = mkdtempSync(join(tmpdir(), "person-chains-busy-"));
  const chains = new PersonChains(data);
  chains.keep(pin, old);
  lock.add("device.remove", { key: lock.first.key.id }, second.key);
  const path = join(data, "mesh", "person-locks.sqlite");
  const writer = new DatabaseSync(path);
  writer.exec("BEGIN IMMEDIATE");
  const started = performance.now();
  assert.throws(() => chains.keep(pin, lock.chain), /try again/);
  console.log(`PERSON_LOCK_BUSY_MS ${(performance.now() - started).toFixed(3)}`);
  writer.exec("ROLLBACK");
  writer.close();
  chains.keep(pin, lock.chain);

  const script = `const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync(process.argv[1]); db.exec('BEGIN IMMEDIATE'); db.prepare('UPDATE chains SET entries = ? WHERE genesis = ?').run('[]', process.argv[2]); process.send('writing'); setInterval(() => {}, 1000);`;
  const child = spawn(process.execPath, ["-e", script, path, pin], { stdio: ["ignore", "ignore", "ignore", "ipc"] });
  try {
    const [message] = await once(child, "message");
    assert.equal(message, "writing");
  } finally {
    child.kill("SIGKILL");
    await once(child, "exit");
  }
  chains.close();
  const restarted = new PersonChains(data);
  assert.deepEqual(restarted.newest(pin, "carol", old), lock.chain, "the uncommitted replacement was rolled back");
  restarted.close();
});
