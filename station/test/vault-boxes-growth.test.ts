import assert from "node:assert/strict";
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import type { LockState } from "../src/cloud/lock.ts";
import { routes } from "../src/api/routes/vault.ts";
import { certOk, signedBytes, TAG, type BoxCert } from "../src/vault/crypto.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture() {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string; seed: string }; device: { id: string }; cert: BoxCert;
  };
  const db = new DatabaseSync(":memory:");
  let inspected = 0;
  db.function("box_seen", (_id: unknown) => { inspected++; return 0; });
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => target.prepare(sql.replace(
      "SELECT body FROM vault_boxes WHERE ws = ?", "SELECT body, box_seen(device) AS seen FROM vault_boxes WHERE ws = ?"));
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const vaults = new VaultStore(observed);
  for (let i = 0; i < 120; i++) vaults.putBox({ ...v.cert, device: i.toString(16).padStart(64, "0") });
  vaults.putBox(v.cert);
  const device = { id: v.device.id, sub: "alice", kind: "app" as const, label: "Alice", own: true, sign_key: v.signer.key };
  const member = { sub: "alice", email: "a@example.test", role: "owner" as const };
  const state = { ws: v.ws, devices: new Map([[device.id, device]]), members: new Map([[member.sub, member]]), signKeys: new Map() } as LockState;
  const route = routes({ vaults, lock: () => state }).find((r) => r.method === "GET" && r.pattern.test("/vault/boxes"))!;
  const request: Request = { method: "GET", path: "/vault/boxes", query: [], headers: {}, body: Buffer.alloc(0),
    viewer: { sub: "alice", workspace: v.ws, email: "a@example.test", name: "Alice", role: "owner", device: v.device.id }, lang: "en" };
  const read = async () => {
    inspected = 0;
    const answer = await route.handle(request, []);
    return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()), inspected };
  };
  const signedFor = (id: string): BoxCert => {
    const { sig: _, ...unsigned } = { ...v.cert, device: id };
    const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.from(v.signer.seed, "hex")]), format: "der", type: "pkcs8" });
    return { ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(unsigned, TAG.box), key).toString("hex") } };
  };
  return { v, db, vaults, state, device, member, read, signedFor };
}

test("listing current box certificates need not read every removed device's certificate", async () => {
  const f = fixture();
  try {
    assert.equal(certOk(f.state, f.v.cert), null);
    const answer = await f.read();
    assert.equal(answer.status, 200);
    assert.deepEqual(answer.body.boxes, [f.v.cert]);
    assert.ok(answer.inspected <= 32, `read ${answer.inspected} certificates`);
  } finally { f.db.close(); }
});

test("selected certificates retain their order and still use the current lock and signatures", async () => {
  const f = fixture();
  try {
    const second = f.signedFor("a".repeat(64));
    f.vaults.putBox(second);
    f.state.devices.set(second.device, { ...f.device, id: second.device });
    assert.equal(certOk(f.state, second), null);
    assert.deepEqual((await f.read()).body.boxes, [second, f.v.cert]);
    f.state.devices.delete(f.v.device.id);
    assert.deepEqual((await f.read()).body.boxes, [second]);
    f.state.devices.set(second.device, { ...f.device, id: second.device, own: false });
    assert.deepEqual((await f.read()).body.boxes, []);
    f.state.devices.set(second.device, { ...f.device, id: second.device, sign_key: `ed25519:${"0".repeat(64)}` });
    assert.deepEqual((await f.read()).body.boxes, []);
    f.state.devices.set(second.device, { ...f.device, id: second.device });
    f.state.members.delete(f.member.sub);
    assert.deepEqual((await f.read()).body.boxes, []);
    f.state.members.set(f.member.sub, f.member);
    f.vaults.putBox({ ...second, sig: { ...second.sig, sig: "0".repeat(128) } });
    assert.deepEqual((await f.read()).body.boxes, []);
  } finally { f.db.close(); }
});

test("certificate results remain the same around the small lock boundary", async () => {
  const f = fixture();
  try {
    for (const count of [31, 32, 33]) {
      while (f.state.devices.size < count) {
        const id = `e${f.state.devices.size.toString(16).padStart(63, "0")}`;
        f.state.devices.set(id, { ...f.device, id });
      }
      const answer = await f.read();
      assert.deepEqual(answer.body.boxes, [f.v.cert]);
      if (count <= 32) assert.ok(answer.inspected <= 32, `read ${answer.inspected} certificates`);
    }
  } finally { f.db.close(); }
});

test("a lock without any devices has no current certificates", async () => {
  const f = fixture();
  try {
    f.state.devices.clear();
    const answer = await f.read();
    assert.deepEqual(answer.body.boxes, []);
    assert.equal(answer.inspected, 0);
  } finally { f.db.close(); }
});

test("an unreadable removed certificate does not block a small lock's current certificate", async () => {
  const f = fixture();
  try {
    f.db.prepare("UPDATE vault_boxes SET body=? WHERE ws=? AND device=?").run("{broken", f.v.ws, "0".repeat(64));
    assert.deepEqual((await f.read()).body.boxes, [f.v.cert]);
    f.db.prepare("UPDATE vault_boxes SET body=? WHERE ws=? AND device=?").run("{broken", f.v.ws, f.v.device.id);
    await assert.rejects(f.read(), SyntaxError);
    f.vaults.putBox(f.v.cert);
    while (f.state.devices.size <= 32) {
      const id = `e${f.state.devices.size.toString(16).padStart(63, "0")}`;
      f.state.devices.set(id, { ...f.device, id });
    }
    await assert.rejects(f.read(), SyntaxError);
  } finally { f.db.close(); }
});
