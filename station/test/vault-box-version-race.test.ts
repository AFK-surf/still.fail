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

test("an older certificate validated before a newer one does not replace it", async () => {
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
  const stale = makeCert(1100, 4), newer = makeCert(1200, 5);
  assert.equal(certOk(state, stale), null);
  assert.equal(certOk(state, newer), null);
  const dir = mkdtempSync(join(process.cwd(), "vault-box-version-"));
  const db = new DatabaseSync(join(dir, "data.sqlite")), other = new DatabaseSync(join(dir, "data.sqlite"));
  try {
    db.exec("PRAGMA journal_mode=WAL");
    const vaults = new VaultStore(db), fromOther = new VaultStore(other);
    vaults.putBox(v.cert);
    let raced = false;
    const interleaved = new Proxy(vaults, { get(target, property) {
      if (property === "putBox") return (cert: BoxCert) => {
        if (!raced) { raced = true; fromOther.putBox(newer); }
        return target.putBox(cert);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const boxed: BoxCert[] = [];
    const route = routes({ vaults: interleaved, lock: () => state, boxed: (_lock, cert) => boxed.push(cert) })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/boxes"))!;
    const request: Request = { method: "PUT", path: "/vault/boxes", query: [], headers: {}, body: Buffer.from(JSON.stringify(stale)),
      viewer: { sub: "alice", workspace: v.ws, email: "a@x", name: "Alice", role: "owner", device: v.device.id }, lang: "en" };
    const answer = await route.handle(request, []);
    assert.equal(raced, true);
    assert.deepEqual(vaults.box(v.ws, v.device.id), newer);
    assert.deepEqual(JSON.parse((answer.body as Buffer).toString()).box, newer);
    assert.deepEqual(boxed, []);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
