// A person's own lock as the cloud keeps it (src/personal-lock.ts): each entry following the last
// and signed by a device on it; a chain begun anew is taken (all of a person's devices lost), and devices decide whether
// to follow it. Hashes and signatures are the stations' and the core's.
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import { entryHash, signedBytes, type Entry } from "../../station/src/cloud/lock.ts";
import { personFold } from "../../station/src/cloud/lock.ts";
import { extendPersonal, extendPersonalKept, type PersonalEntry } from "../src/personal-lock.ts";

const SUB = "s1";

function key() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  return { id: `ed25519:${raw.toString("hex")}`, privateKey };
}

function entry(by: ReturnType<typeof key>, seq: number, prev: string | null, kind: string, body: unknown, ws = `person:${SUB}`): PersonalEntry {
  const e = { v: 1 as const, ws, seq, prev, at: 1, kind, body };
  const hash = entryHash(e as unknown as Entry);
  return { ...e, sig: { key: by.id, alg: "Ed25519", sig: sign(null, signedBytes(hash), by.privateKey).toString("hex") } };
}
const hashOf = (e: PersonalEntry) => entryHash(e as unknown as Entry);
const device = (k: ReturnType<typeof key>) => ({ key: k.id, id: "ab".repeat(32), label: "x" });

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

test("a chain with web devices and a workspace's commitments is kept as it is; one of today as before", () => {
  // (rules/src/lock/person.mbt: `web {id, label, exp}`, `web.remove {id}`, `ws {t, h}`, signed by a device on the log;
  // nothing signs them yet, every part takes them from the rules' build on)
  const a = key();
  const first = entry(a, 0, null, "genesis", { sub: SUB, device: device(a) });
  const today = extendPersonal(SUB, [], [first]);
  assert.deepEqual(personFold(today, SUB).devices.map((d) => d.key), [a.id]);
  const web = entry(a, 1, hashOf(first), "web", { id: "bb".repeat(32), label: "a browser", exp: 1 + 31 * 86400 });
  const ws = entry(a, 2, hashOf(web), "ws", { t: "cc".repeat(32), h: "dd".repeat(32) });
  const gone = entry(a, 3, hashOf(ws), "web.remove", { id: "bb".repeat(32) });
  const kept = extendPersonal(SUB, today, [web, ws, gone]);
  assert.equal(kept.length, 4);
  assert.deepEqual(personFold(kept, SUB).devices.map((d) => d.key), [a.id], "its devices as they were");
  // As another keeper's, by the fork choice, too.
  assert.equal(extendPersonalKept(SUB, { entries: today, aside: [] }, [first, web, ws, gone]).entries.length, 4);
  // Round three's statements in the clear: refused, as before.
  assert.throws(() => extendPersonal(SUB, kept, [entry(a, 4, hashOf(gone), "ws.member", { ws: "w1", sub: "dan", lock: "ee".repeat(32), role: "member" })]), /lock_refused/);
  // Past its bounds: refused.
  assert.throws(() => extendPersonal(SUB, today, [entry(a, 1, hashOf(first), "web", { id: "bb".repeat(32), label: "x", exp: 1 + 31 * 86400 + 1 })]), /lock_refused/);
});
