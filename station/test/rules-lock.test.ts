// The workspace lock's rules as rules/ (MoonBit) has them, as station/src/cloud/lock.ts calls them, against the
// TypeScript they replaced (lock-oracle.ts): on
// seeded random chains (each entry of a random kind, its body well formed or not, signed by a key in the lock or not,
// following the head or not), every prefix folds to the same state or is refused with the same words, and each device
// is let in or turned away the same. The cryptography is the stations' own on both sides.
import assert from "node:assert/strict";
import { createHash, createPrivateKey, createPublicKey, sign as nodeSign } from "node:crypto";
import { test } from "node:test";
import { type Entry, type LockState, admit as stationAdmit, endpointBytes, endpointProof, entryHash, fold as stationFold, signedBytes, sigValid, validKeyId } from "../src/cloud/lock.ts";
import { admit, fold } from "./lock-oracle.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const crypto = {
  sha256Hex: (s: string) => createHash("sha256").update(s).digest("hex"),
  sigValid, validKeyId, endpointProof,
};

function rng(seed: number) {
  let s = seed >>> 0;
  const next = () => {
    let x = (s += 0x6d2b79f5);
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  return { next, int: (n: number) => Math.floor(next() * n), pick: <T>(xs: T[]): T => xs[Math.floor(next() * xs.length)]! };
}

function key(n: number) {
  const seed = Buffer.alloc(32);
  seed.writeUInt32BE(n, 28);
  const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]), format: "der", type: "pkcs8" });
  const hex = Buffer.from(createPublicKey(privateKey).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (b: Buffer) => nodeSign(null, b, privateKey).toString("hex") };
}

const WS = "01HRULESRULESRULESRULESRUL";
const people = ["alice", "bob", "carol", "dave"];
const signers = people.map((_, i) => key(10 + i));
const bases = people.map((_, i) => key(20 + i));
const spare = Array.from({ length: 6 }, (_, i) => key(40 + i));
const stranger = key(99);

/// An entry's hash; one that has none (its `at` no integer) hashed as nothing, refused before its hash is looked at.
const hashOf = (e: Omit<Entry, "sig">) => {
  try {
    return entryHash(e as Entry);
  } catch {
    return "00".repeat(32);
  }
};

const signed = (e: Omit<Entry, "sig">, k = signers[0]!, broken = false): Entry => {
  const hash = hashOf(e);
  const sig = { key: k.id, alg: "Ed25519" as const, sig: k.sign(signedBytes(hash)) };
  return { ...e, sig: broken ? { ...sig, sig: "00" + sig.sig.slice(2) } : sig };
};

function genesisOf(r: ReturnType<typeof rng>): Entry {
  const roles = ["owner", r.pick(["admin", "member", "viewer"]), r.pick(["member", "admin"]), "viewer"];
  return signed({
    v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
      owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
      members: people.map((p, i) => ({ sub: p, email: `${p}@x`, role: roles[i] })),
      devices: people.slice(0, 3).map((p, i) => ({ id: bases[i]!.hex, sub: p, kind: "app", label: p, sign_key: signers[i]!.id })),
      passkeys: [], stations: [{ key: key(60).hex, name: "s0" }], gateways: [],
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
      else if (r.int(2) === 0) d.sign_key = r.pick([...signers, ...spare]).id;
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
    case "passkey": return { id: "pk1", sub, key: "p256:nope", label: "" };
    default: return {};
  }
}

const KINDS = ["member", "member", "member.remove", "device", "device", "device", "device", "device.remove", "device.remove", "station", "station.remove", "gateway", "gateway.remove", "cloud_keys", "passkey", "passkey.remove", "bogus"];

/// The next entry of a random chain: after its last kept entry (or, now and then, not), signed by someone in the lock
/// or not, its signature now and then broken.
function nextOf(r: ReturnType<typeof rng>, last: Entry, i: number): Entry {
  const offHead = r.int(12) === 0;
  const e = {
    v: 1 as const, ws: r.int(30) === 0 ? "other" : WS, seq: offHead ? last.seq + 2 : last.seq + 1, prev: hashOf(last),
    // (turned off now and then: nothing after it is taken)
    at: r.int(20) === 0 ? 1.5 : 1000 + i * 60, kind: r.int(60) === 0 ? "disable" : r.pick(KINDS), body: {} as any,
  };
  e.body = bodyOf(r, e.kind);
  return signed(e, r.int(10) === 0 ? stranger : r.int(2) === 0 ? signers[0]! : r.pick([...signers, ...spare.slice(0, 2)]), r.int(25) === 0);
}

/// The TypeScript's state as the MoonBit's is written (maps as [key, value] pairs in their order).
function plain(s: LockState): unknown {
  const pairs = <V>(m: Map<string, V>) => [...m].map(([k, v]) => [k, v]);
  return JSON.parse(JSON.stringify({
    ws: s.ws, seq: s.seq, head: s.head, genesis: s.genesis, origins: s.origins, rp_id: s.rp_id, cloud_keys: s.cloud_keys,
    members: pairs(s.members), devices: pairs(s.devices), signKeys: pairs(s.signKeys), passkeys: pairs(s.passkeys), signed: [...s.signed],
    stations: pairs(s.stations), gateways: [...s.gateways], disabled: s.disabled,
  }));
}

const tsFold = (entries: Entry[], now: number | null, f = fold) => {
  try {
    return { state: plain(f(entries, now)) };
  } catch (e) {
    return { error: (e as Error).message };
  }
};

const SEEDS = Number(process.env.RULES_SEEDS ?? 50);

test("the MoonBit lock rules fold every prefix of random chains as the TypeScript did, and admit the same devices", () => {
  let folded = 0, refused = 0;
  const t0 = performance.now(); let tsMs = 0, mbMs = 0;
  const reasons = new Map<string, number>();
  for (let seed = 1; seed <= SEEDS; seed++) {
    const r = rng(seed);
    // A refused entry is dropped (as a station drops it): the next is made after the last kept.
    const kept: Entry[] = [genesisOf(r)];
    for (let i = 1; i <= 30; i++) {
      const next = nextOf(r, kept.at(-1)!, i);
      const tried = [...kept, next];
      for (const now of [null, 1000 + 20 * 60]) {
        let t = performance.now();
        const ts = tsFold(tried, now);
        tsMs += performance.now() - t;
        t = performance.now();
        const mb = JSON.parse(JSON.stringify(rules.fold_js(tried, now, crypto)));
        mbMs += performance.now() - t;
        assert.deepEqual(mb, ts, `seed ${seed}, entry ${i} (${next.kind}), now ${now}`);
        assert.deepEqual(tsFold(tried, now, stationFold), ts, `station: seed ${seed}, entry ${i} (${next.kind}), now ${now}`);
      }
      const got = tsFold(tried, null);
      if ("state" in got) {
        kept.push(next);
        folded++;
      } else {
        refused++;
        reasons.set(got.error!, (reasons.get(got.error!) ?? 0) + 1);
      }
    }
    // Every device, with and without its proof, at a time before and after a web page's runs out: the same answers.
    const s = fold(kept, null);
    const queries: { sub: string; endpoint: string; base?: string; proof?: string; now: number }[] = [];
    for (const [i, who] of [...bases, ...spare].entries()) {
      const endpoint = spare[(i + 1) % spare.length]!.hex;
      const proof = who.sign(endpointBytes(WS, endpoint));
      for (const sub of people) {
        for (const now of [2000, 1000 + 35 * 86400]) queries.push({ sub, endpoint, base: who.hex, proof, now }, { sub, endpoint: who.hex, now });
      }
    }
    const answers = (s: LockState, f: typeof admit) => queries.map((q) => {
      try {
        const a = f(s, q, q.now);
        return { device: a.device.id, role: a.role };
      } catch (e) {
        return { refusal: (e as Error).message };
      }
    });
    const ts = answers(s, admit);
    assert.deepEqual(JSON.parse(JSON.stringify(rules.admit_js(kept, null, queries, crypto))), ts, `seed ${seed}: admitted otherwise`);
    assert.deepEqual(answers(stationFold(kept, null), stationAdmit), ts, `station: seed ${seed}: admitted otherwise`);
  }
  if (process.env.RULES_TRACE) console.error(`${Math.round(performance.now() - t0)} ms: TypeScript folds ${Math.round(tsMs)} ms, MoonBit ${Math.round(mbMs)} ms; ${folded} taken, ${refused} refused`, [...reasons].sort((a, b) => b[1] - a[1]));
  // (the chains try both: most entries refused would test little)
  assert.ok(folded > SEEDS * 5 && refused > SEEDS * 5, `${folded} taken, ${refused} refused`);
});
