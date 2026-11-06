// A person's own lock in a workspace's (rules/src/lock/person.mbt, docs/personal-lock.md): only a member's own device
// binds a lock to them, a chain holds only as signed by a device on it, and a device is let in on it only as the
// lock bound there says, not on one taken off since, nor on another lock.
import assert from "node:assert/strict";
import { generateKeyPairSync, sign as nodeSign } from "node:crypto";
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
