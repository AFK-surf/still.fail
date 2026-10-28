// Lock entries signed as an owner's app signs them (station/src/cloud/lock.ts): what the cloud takes, as a station would.
import { generateKeyPairSync, sign } from "node:crypto";
import { entryHash, type LockEntry } from "../src/lock.ts";

/** An app's signing key, and the device that holds it (whose: `sub`). */
export function signer(sub: string) {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const key = `ed25519:${Buffer.from(publicKey.export({ format: "jwk" }).x!, "base64url").toString("hex")}`;
  const device = { id: Buffer.from(publicKey.export({ format: "jwk" }).x!, "base64url").toString("hex"), sub, kind: "app", label: "", sign_key: key };
  return {
    key,
    /** A genesis of `sub` as the owner, this device in it (`more`: the rest of its body). */
    genesis: (ws: string, more: Record<string, unknown> = {}) =>
      signed(ws, null, "genesis", { owner: sub, origins: [], rp_id: "", cloud_keys: null, members: [{ sub, email: `${sub}@example.test`, role: "owner" }], devices: [device], passkeys: [], stations: [], gateways: [], ...more }),
    /** An entry after `prev` (none: a genesis). */
    entry: (ws: string, prev: LockEntry | null, kind: string, body: unknown) => signed(ws, prev, kind, body),
  };

  async function signed(ws: string, prev: LockEntry | null, kind: string, body: unknown): Promise<LockEntry> {
    const e = { v: 1 as const, ws, seq: prev ? prev.seq + 1 : 0, prev: prev ? await entryHash(prev) : null, at: 1000, kind, body, sig: null };
    const hash = await entryHash(e);
    const bytes = Buffer.concat([Buffer.from("stillfail-lock/1 sig\0"), Buffer.from(hash, "hex")]);
    return { ...e, sig: { key, alg: "Ed25519", sig: sign(null, bytes, privateKey).toString("hex") } };
  }
}
