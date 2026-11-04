// Random workspace lock chains, seeded: each entry of a random kind, its body well formed or not, signed by a key in the
// lock or not, following the head or not; signed with Ed25519 and P-256 app keys and with passkeys (WebAuthn), as
// devices sign. What rules-lock.test.ts (station) and lock-rules.test.ts (the core) fold.
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { type Entry, type Sig, entryHash, signedBytes } from "../src/cloud/lock.ts";

export function rng(seed: number) {
  let s = seed >>> 0;
  const next = () => {
    let x = (s += 0x6d2b79f5);
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  return { next, int: (n: number) => Math.floor(next() * n), pick: <T>(xs: T[]): T => xs[Math.floor(next() * xs.length)]! };
}

export function key(n: number) {
  const seed = Buffer.alloc(32);
  seed.writeUInt32BE(n, 28);
  const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]), format: "der", type: "pkcs8" });
  const hex = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  const sign = (b: Buffer) => nodeSign(null, b, privateKey).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign, sigOver: (hash: string): Sig => ({ key: `ed25519:${hex}`, alg: "Ed25519", sig: sign(signedBytes(hash)) }) };
}

/// A P-256 key (made anew each run: node makes none from a seed), its id `p256:<base64url of the uncompressed point>`.
function p256() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const id = `p256:${Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url")}`;
  return { privateKey, id };
}

/// An app device's P-256 signing key (ES256, the signature as IEEE P1363).
function appP256() {
  const { privateKey, id } = p256();
  return { id, sigOver: (hash: string): Sig => ({ key: id, alg: "ES256", sig: nodeSign("sha256", signedBytes(hash), { key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url") }) };
}

/// A passkey: a WebAuthn assertion on `origin` for the lock's relying party, the entry's hash its challenge.
function passkey(origin = "https://app.still.fail") {
  const { privateKey, id } = p256();
  const sha = (b: Buffer | string) => createHash("sha256").update(b).digest();
  return {
    id,
    sigOver: (hash: string, on = origin): Sig => {
      const client = Buffer.from(JSON.stringify({ type: "webauthn.get", challenge: Buffer.from(hash, "hex").toString("base64url"), origin: on }));
      const auth = Buffer.concat([sha("app.still.fail"), Buffer.from([1, 0, 0, 0, 0])]);
      const sig = nodeSign("sha256", Buffer.concat([auth, sha(client)]), { key: privateKey, dsaEncoding: "der" });
      return { key: id, alg: "webauthn", authenticator_data: auth.toString("base64url"), client_data: client.toString("base64url"), sig: sig.toString("base64url") };
    },
  };
}

export const WS = "01HRULESRULESRULESRULESRUL";
export const people = ["alice", "bob", "carol", "dave"];
export const signers = people.map((_, i) => key(10 + i));
export const bases = people.map((_, i) => key(20 + i));
export const spare = Array.from({ length: 6 }, (_, i) => key(40 + i));
export const p256s = [appP256(), appP256()];
export const passkeys = [passkey(), passkey()];
const stranger = key(99);
type Signs = { id: string; sigOver: (hash: string, origin?: string) => Sig };

/// An entry's hash; one that has none (its `at` no integer) hashed as nothing, refused before its hash is looked at.
const hashOf = (e: Omit<Entry, "sig">) => {
  try {
    return entryHash(e as Entry);
  } catch {
    return "00".repeat(32);
  }
};

/// Signed by `k`; `broken`: its signature's first bytes changed; `origin`: a passkey's on another page.
const signed = (e: Omit<Entry, "sig">, k: Signs = signers[0]!, broken = false, origin?: string): Entry => {
  const sig = k.sigOver(hashOf(e), origin);
  return { ...e, sig: broken ? { ...sig, sig: (sig.sig.startsWith("AA") ? "BB" : "AA") + sig.sig.slice(2) } : sig } as Entry;
};

export function genesisOf(r: ReturnType<typeof rng>): Entry {
  const roles = ["owner", r.pick(["admin", "member", "viewer"]), r.pick(["member", "admin"]), "viewer"];
  return signed({
    v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
      owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
      members: people.map((p, i) => ({ sub: p, email: `${p}@x`, role: roles[i] })),
      // (alice's second app device signs with P-256, as an iPhone's Secure Enclave key does)
      devices: [
        ...people.slice(0, 3).map((p, i) => ({ id: bases[i]!.hex, sub: p, kind: "app", label: p, sign_key: i === 2 && r.int(2) === 0 ? p256s[0]!.id : signers[i]!.id })),
        { id: key(61).hex, sub: "alice", kind: "app", label: "alice P-256", sign_key: p256s[1]!.id },
      ],
      passkeys: r.int(4) !== 0 ? [{ id: "pk-alice", sub: "alice", key: passkeys[0]!.id, label: "Mac" }] : [], stations: [{ key: key(60).hex, name: "s0" }], gateways: [],
    },
  });
}

/// A body for `kind`, well formed or (now and then) not.
function bodyOf(r: ReturnType<typeof rng>, kind: string): unknown {
  const sub = r.int(6) === 0 ? r.pick(["eve", ""]) : r.pick(people);
  const dev = r.pick([...bases, ...spare]);
  const broken = r.int(8) === 0;
  switch (kind) {
    case "member": return broken ? { sub, role: "god" } : { sub, email: `${sub}@x`, role: r.pick(["owner", "admin", "member", "viewer"]) };
    case "member.remove": return { sub };
    case "device": {
      const web = r.int(3) === 0;
      const d: Record<string, unknown> = { id: broken ? "nothex" : dev.hex, sub, kind: web ? "web" : "app", label: r.pick(["phone", "名字 😀", "x".repeat(250)]) };
      if (web) d.exp = r.pick([1000 + 86400, 1000 + 40 * 86400, 5000]);
      else if (r.int(2) === 0) d.sign_key = r.pick([...signers, ...spare, ...p256s]).id;
      if (r.int(6) === 0) d.endpoints = [r.pick(spare).hex];
      if (r.int(10) === 0) d.sign_key = null;
      return d;
    }
    case "device.remove": return { id: dev.hex };
    case "station": return broken ? { key: "x" } : { key: r.pick(spare).hex, name: "st" };
    case "station.remove": return { key: r.pick(spare).hex };
    case "gateway": return { key: broken ? 5 : r.pick(spare).hex };
    case "gateway.remove": return { key: r.pick(spare).hex };
    case "cloud_keys": return broken ? {} : { keys: { keys: [{ kid: "k2" }] } };
    case "passkey": return { id: r.pick(["pk1", "pk2"]), sub, key: r.pick([...passkeys.map((p) => p.id), passkeys[0]!.id, "p256:nope"]), label: "" };
    case "passkey.remove": return { key: r.pick(passkeys).id };
    default: return {};
  }
}

const KINDS = ["member", "member", "member.remove", "device", "device", "device", "device", "device.remove", "device.remove", "station", "station.remove", "gateway", "gateway.remove", "cloud_keys", "passkey", "passkey.remove", "bogus"];

/// The next entry of a random chain: after its last kept entry (or, now and then, not), signed by someone in the lock
/// or not, its signature now and then broken.
export function nextOf(r: ReturnType<typeof rng>, last: Entry, i: number): Entry {
  const offHead = r.int(12) === 0;
  const e = {
    v: 1 as const, ws: r.int(30) === 0 ? "other" : WS, seq: offHead ? last.seq + 2 : last.seq + 1, prev: hashOf(last),
    // (turned off now and then: nothing after it is taken)
    at: r.int(20) === 0 ? 1.5 : 1000 + i * 60, kind: r.int(60) === 0 ? "disable" : r.pick(KINDS), body: {} as any,
  };
  e.body = bodyOf(r, e.kind);
  const by: Signs = r.int(10) === 0 ? stranger : r.int(2) === 0 ? signers[0]! : r.pick([...signers, ...spare.slice(0, 2), ...p256s, ...passkeys]);
  return signed(e, by, r.int(25) === 0, r.int(15) === 0 ? "https://elsewhere.example" : undefined);
}

