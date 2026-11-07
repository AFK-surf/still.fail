import assert from "node:assert/strict";
import { createPrivateKey, sign } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { type Entry, admit, entryHash, genesis, signedBytes as lockBytes } from "../src/cloud/lock.ts";
import type { Request } from "../src/api/request.ts";
import { routes } from "../src/api/routes/vault.ts";
import { boxPublic, certOk, signedBytes, TAG, type BoxCert } from "../src/vault/crypto.ts";
import { VaultStore } from "../src/vault/store.ts";
import { vaultWriteGate } from "../src/vault/write-gate.ts";

function fixture() {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string; seed: string }; device: { id: string }; cert: BoxCert;
  };
  const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.from(v.signer.seed, "hex")]), format: "der", type: "pkcs8" });
  const body = { owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }],
    devices: [{ id: v.device.id, sub: "alice", kind: "app", label: "alice", sign_key: v.signer.key }], passkeys: [], stations: [], gateways: [] };
  const unsigned = { v: 1, ws: v.ws, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">;
  const state = genesis({ ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, lockBytes(entryHash(unsigned as Entry)), key).toString("hex") } });
  assert.equal(admit(state, { sub: "alice", endpoint: v.device.id }, 0).device.id, v.device.id);
  const makeCert = (at: number, keyByte: number): BoxCert => {
    const { sig: _, ...base } = v.cert;
    const next = { ...base, at, box: boxPublic(new Uint8Array(32).fill(keyByte)) };
    return { ...next, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(next, TAG.box), key).toString("hex") } };
  };
  const dir = mkdtempSync(join(process.cwd(), "vault-box-version-"));
  const db = new DatabaseSync(join(dir, "data.sqlite")), other = new DatabaseSync(join(dir, "data.sqlite"));
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db), fromOther = new VaultStore(other);
  const request = (cert: BoxCert): Request => ({ method: "PUT", path: "/vault/boxes", query: [], headers: {}, body: Buffer.from(JSON.stringify(cert)),
    viewer: { sub: "alice", workspace: v.ws, email: "a@x", name: "Alice", role: "owner", device: v.device.id }, lang: "en" });
  let oldClosed = false;
  const closeOther = () => { if (!oldClosed) { other.close(); oldClosed = true; } };
  const close = () => { closeOther(); db.close(); rmSync(dir, { recursive: true, force: true }); };
  return { v, db, other, state, makeCert, vaults, fromOther, request, closeOther, close };
}

test("an older certificate validated before a newer one does not replace it", async () => {
  const f = fixture();
  try {
    const stale = f.makeCert(1100, 4), newer = f.makeCert(1200, 5);
    assert.equal(certOk(f.state, stale), null);
    assert.equal(certOk(f.state, newer), null);
    f.vaults.putBox(f.v.cert);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putBoxIf") return (cert: BoxCert, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putBox(newer); }
        return target.putBoxIf(cert, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const boxed: BoxCert[] = [];
    const route = routes({ vaults: interleaved, lock: () => f.state, boxed: (_lock, cert) => { boxed.push(cert); } })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    const answer = await route.handle(f.request(stale), []);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.box(f.v.ws, f.v.device.id), newer);
    assert.deepEqual(JSON.parse((answer.body as Buffer).toString()).box, newer);
    assert.deepEqual(boxed, [newer], "only the certificate actually held can be reboxed");
  } finally { f.close(); }
});

test("a newer certificate is retried if another connection writes an older one", async () => {
  const f = fixture();
  try {
    const newer = f.makeCert(1200, 5), other = f.makeCert(1100, 4);
    const boxed: BoxCert[] = [];
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putBoxIf") return (cert: BoxCert, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putBox(other); }
        return target.putBoxIf(cert, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const put = routes({ vaults: interleaved, lock: () => f.state, boxed: (_lock, cert) => { boxed.push(cert); } })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    const answer = await put.handle(f.request(newer), []);
    assert.equal(raced, true);
    assert.equal(answer.status, 200);
    assert.deepEqual(f.vaults.box(f.v.ws, f.v.device.id), newer);
    assert.deepEqual(boxed, [newer]);
  } finally { f.close(); }
});

test("certificates with the same timestamp keep the existing last-write behavior", async () => {
  const f = fixture();
  try {
    const one = f.makeCert(1200, 4), other = f.makeCert(1200, 5);
    f.vaults.putBox(one);
    const boxed: BoxCert[] = [];
    const put = routes({ vaults: f.vaults, lock: () => f.state, boxed: (_lock, cert) => { boxed.push(cert); } })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    assert.equal((await put.handle(f.request(other), [])).status, 200);
    assert.deepEqual(f.vaults.box(f.v.ws, f.v.device.id), other);
    assert.deepEqual(boxed, [other]);
  } finally { f.close(); }
});

test("a certificate waits for old prepared writes, then checks the last one", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    const stale = f.makeCert(1100, 4), newer = f.makeCert(1200, 5);
    f.vaults.putBox(f.v.cert);
    const old = f.other.prepare("INSERT INTO vault_boxes (ws, device, body) VALUES (?, ?, ?) ON CONFLICT (ws, device) DO UPDATE SET body = excluded.body");
    const boxed: BoxCert[] = [];
    const put = routes({ vaults: f.vaults, lock: () => f.state, beforeWrite: () => gate.wait(), boxed: (_lock, cert) => { boxed.push(cert); } })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    let answered = false;
    const pending = put.handle(f.request(stale), []).then((answer) => { answered = true; return answer; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(answered, false);
    old.run(newer.ws, newer.device, JSON.stringify(newer));
    f.closeOther(); previous.resolve();
    const answer = await pending;
    assert.deepEqual(JSON.parse((answer.body as Buffer).toString()).box, newer);
    assert.deepEqual(f.vaults.box(f.v.ws, f.v.device.id), newer);
    assert.deepEqual(boxed, [newer]);
  } finally { gate.close(); f.close(); }
});

test("a failed certificate write sends no reboxing notification", async () => {
  const f = fixture();
  try {
    f.db.exec("CREATE TRIGGER reject_box BEFORE INSERT ON vault_boxes BEGIN SELECT RAISE(ABORT, 'box write failed'); END");
    const boxed: BoxCert[] = [];
    const put = routes({ vaults: f.vaults, lock: () => f.state, boxed: (_lock, cert) => { boxed.push(cert); } })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    await assert.rejects(put.handle(f.request(f.makeCert(1100, 4)), []), /box write failed/);
    assert.equal(f.vaults.box(f.v.ws, f.v.device.id), null);
    assert.deepEqual(boxed, []);
  } finally { f.close(); }
});

test("a reboxing conflict asks the device to retry and can finish with a newer certificate", async () => {
  const f = fixture();
  try {
    const first = f.makeCert(1100, 4), newer = f.makeCert(1200, 5);
    const boxed: BoxCert[] = [];
    const put = routes({ vaults: f.vaults, lock: () => f.state, boxed: (_lock, cert) => {
      boxed.push(cert);
      return boxed.length > 1;
    } }).find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    assert.equal((await put.handle(f.request(first), [])).status, 503);
    assert.deepEqual(f.vaults.box(f.v.ws, f.v.device.id), first);
    f.fromOther.putBox(newer);
    const retried = await put.handle(f.request(first), []);
    assert.equal(retried.status, 200);
    assert.deepEqual(JSON.parse((retried.body as Buffer).toString()).box, newer);
    assert.deepEqual(boxed, [first, newer]);
  } finally { f.close(); }
});
