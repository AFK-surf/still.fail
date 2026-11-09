// The mesh addon's signature check (native/mesh/src/verify.rs: libcrux, formally verified) answers as node's does, on
// signatures good and bad of each kind a lock entry, a device's endpoint proof and a vault record carry: what the station
// checks them by where the addon has it (cloud/lock.ts `verifyWith`). Without the addon (a checkout that built none):
// skipped.
import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { test } from "node:test";
import { signatureOk, verifyWith } from "../src/cloud/lock.ts";
import { loadMesh } from "../src/mesh/native.ts";

const mesh = (() => {
  try {
    return loadMesh();
  } catch {
    return null;
  }
})();

test("the mesh addon's libcrux answers as node's, signature by signature", { skip: !mesh?.verify && "no mesh addon with verify here" }, () => {
  const ed = generateKeyPairSync("ed25519");
  const p = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const edId = `ed25519:${Buffer.from(ed.publicKey.export({ format: "jwk" }).x!, "base64url").toString("hex")}`;
  const jwk = p.publicKey.export({ format: "jwk" });
  const pId = `p256:${Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url")}`;
  const cases: [string, Buffer, Buffer, boolean][] = [];
  for (let i = 0; i < 200; i++) {
    const msg = randomBytes(1 + (i % 90));
    const other = Buffer.concat([msg, Buffer.from([i & 255])]);
    const e = sign(null, msg, ed.privateKey);
    const r = sign("sha256", msg, { key: p.privateKey, dsaEncoding: "ieee-p1363" });
    const d = sign("sha256", msg, { key: p.privateKey, dsaEncoding: "der" });
    const broken = (b: Buffer) => Buffer.from(b.map((x, j) => (j === i % b.length ? x ^ 1 : x)));
    cases.push([edId, e, msg, false], [edId, e, other, false], [edId, broken(e), msg, false]);
    cases.push([pId, r, msg, false], [pId, r, other, false], [pId, broken(r), msg, false]);
    cases.push([pId, d, msg, true], [pId, broken(d), msg, true]);
  }
  const answers = (on: boolean) => {
    verifyWith(on ? (alg, key, signature, message) => mesh!.verify!(alg, key, signature, message) : null);
    try {
      return cases.map(([id, s, m, der]) => {
        try {
          return signatureOk(id, s, m, der);
        } catch {
          return false;
        }
      });
    } finally {
      verifyWith(null);
    }
  };
  const node = answers(false), native = answers(true);
  assert.deepEqual(native, node);
  assert.ok(node.filter(Boolean).length >= 600 && node.filter((x) => !x).length >= 1000, "both good and bad ones, of each kind");
});
