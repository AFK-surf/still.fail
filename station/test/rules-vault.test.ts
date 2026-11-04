// The vault's rules as rules/ (MoonBit) has them, as station/src/vault/crypto.ts calls them, against the TypeScript
// they replaced (vault-oracle.ts): on seeded random locks (lock-chains.ts) and random box certificates, vault versions
// and item versions (each now and then of a wrong shape, signed by a key that may not sign it, or forged), the same
// answer in the same words, first versions and following ones, kept and brought as copies.
import assert from "node:assert/strict";
import { test } from "node:test";
import { type Entry, fold } from "../src/cloud/lock.ts";
import { TAG, browserListingOk, certOk, itemOk, signedBytes, signerOf, vaultOk } from "../src/vault/crypto.ts";
import { WS, bases, genesisOf, key, nextOf, people, rng, signers, spare } from "./lock-chains.ts";
import * as oracle from "./vault-oracle.ts";

const SEEDS = Number(process.env.RULES_SEEDS ?? 40);
type R = ReturnType<typeof rng>;
const boxes = Array.from({ length: 4 }, (_, i) => `x25519:${key(70 + i).hex}`);
const ULID = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const ulid = (r: R) => Array.from({ length: 26 }, () => ULID[r.int(ULID.length)]).join("");
const b64 = (r: R, n: number) => Array.from({ length: n }, () => "ABCxyz019_-"[r.int(11)]).join("");

/// Signed under `tag` by a key of the lock's (or not), the signature now and then broken or missing.
function signed<T extends Record<string, unknown>>(r: R, o: T, tag: string, k = r.pick([...signers, ...spare.slice(0, 2)])): T & { sig: unknown } {
  // (a record with no canonical text, a number not whole in it, signed over nothing: refused before its signature)
  let bytes: Buffer;
  try {
    bytes = Buffer.from(signedBytes(o, tag));
  } catch {
    bytes = Buffer.alloc(0);
  }
  const sig = { key: k.id, alg: "Ed25519", sig: k.sign(bytes) };
  const roll = r.int(20);
  return { ...o, sig: roll === 0 ? { ...sig, sig: "00" + sig.sig.slice(2) } : roll === 1 ? { key: k.id, alg: "RSA", sig: "x" } : roll === 2 ? undefined : sig };
}

function certOf(r: R): any {
  const i = r.int(people.length);
  const odd = r.int(10) === 0;
  const c: Record<string, unknown> = {
    v: odd && r.int(2) ? 2 : 1, ws: r.int(25) === 0 ? "other" : WS,
    device: r.int(12) === 0 ? r.pick(["nothex", 5, [bases[i]!.hex]]) : r.int(6) === 0 ? r.pick(spare).hex : bases[i]!.hex,
    box: r.int(20) === 0 ? "x25519:zz" : r.pick(boxes), at: r.int(25) === 0 ? 1.5 : 1000 + r.int(100),
  };
  return signed(r, c, TAG.box, r.int(4) === 0 ? r.pick([...signers, ...spare]) : signers[i]!);
}

function vaultOf(r: R, prev: any | null): any {
  const owner = prev && r.int(8) ? prev.owner : r.pick(people);
  const members = [owner, ...people.filter((p) => p !== owner && r.int(2) === 0)];
  if (r.int(15) === 0) members.push(r.pick(["eve", "", owner]));
  const keys = Array.from({ length: r.int(4) }, () => (r.int(20) === 0 ? r.pick([null, { cert: certOf(r) }]) : { cert: certOf(r), wrapped: r.int(25) === 0 ? "+bad" : b64(r, 40) }));
  const v: Record<string, unknown> = {
    v: 1, ws: r.int(30) === 0 ? "other" : WS, id: prev && r.int(10) ? prev.id : r.int(12) === 0 ? "v_short" : `v_${ulid(r)}`,
    seq: prev ? prev.seq + r.pick([1, 1, 1, 2, 0, -1]) : r.int(6) === 0 ? 3 : 0, owner, name: r.pick(["Work", "名字 😀", ""]), members,
    epoch: prev ? prev.epoch + r.pick([0, 0, 1, -1]) : r.int(3), keys, at: 1000 + r.int(1000),
  };
  if (r.int(5) === 0) v.recovery = r.int(6) === 0 ? 7 : b64(r, 30);
  if (r.int(5) === 0) v.lasts = r.pick(["once", "hour", "chat", "week"]);
  if (r.int(12) === 0) {
    v.deleted = r.int(4) ? true : "yes";
    if (r.int(2)) v.keys = [];
  }
  if (r.int(25) === 0) v.seq = 1.5;
  const by = r.int(3) === 0 ? r.pick([...signers, ...spare.slice(0, 2)]) : signers[people.indexOf(owner)]!;
  return signed(r, v, TAG.vault, by);
}

function listingOf(r: R): unknown {
  const kind = r.pick(["token", "ssh_key", "login", "file", "browser", "magic"]);
  const l: Record<string, unknown> = {
    name: r.pick(["GitHub", "x".repeat(250)]), kind,
    modes: kind === "browser" && r.int(3) ? ["browser"] : r.pick([["proxy"], ["env", "proxy"], ["browser", "env"], ["ssh", "ssh"], ["telepathy"]]),
    hosts: r.pick([[], ["github.com"], ["*.example.com"], ["Bad Host"], ["a-.com"], ["api.github.com", "x.io"]]),
  };
  if (r.int(4) === 0) l.env = r.pick(["GITHUB_TOKEN", "1BAD", "_ok"]);
  if (r.int(6) === 0) l.lasts = r.pick(["hour", "forever"]);
  return l;
}

function itemOf(r: R, vault: any, prev: any | null): any {
  const deleted = r.int(10) === 0;
  const i: Record<string, unknown> = {
    v: 1, ws: r.int(30) === 0 ? "other" : WS, vault: r.int(20) === 0 ? "v_other" : vault.id, id: prev && r.int(10) ? prev.id : r.int(12) === 0 ? "i_x" : `i_${ulid(r)}`,
    version: prev ? prev.version + r.pick([1, 1, 2, 0]) : r.int(6) === 0 ? 2 : 0, epoch: r.int(5) === 0 ? vault.epoch + r.pick([1, -1]) : vault.epoch,
    ct: deleted ? (r.int(3) ? "" : b64(r, 40)) : r.int(15) === 0 ? b64(r, 10) : r.int(25) === 0 ? "+" + b64(r, 40) : b64(r, 60), at: 1000 + r.int(100),
  };
  if (deleted) i.deleted = r.int(5) ? true : 1;
  if (!deleted && r.int(2)) i.listing = listingOf(r);
  if (deleted && r.int(6) === 0) i.listing = listingOf(r);
  const by = r.int(4) === 0 ? r.pick([...signers, ...spare]) : signers[people.indexOf(r.pick(vault.members?.filter((m: string) => people.includes(m)) ?? people) as string)] ?? signers[0]!;
  return signed(r, i, TAG.item, by);
}

test("the MoonBit vault rules answer random certificates, vaults and items as the TypeScript did, in the same words", () => {
  const counts = { cert: [0, 0], vault: [0, 0], item: [0, 0] };
  const reasons = new Map<string, number>();
  const tally = (what: keyof typeof counts, why: string | null) => {
    counts[what][why === null ? 0 : 1]!++;
    if (why !== null) reasons.set(why, (reasons.get(why) ?? 0) + 1);
  };
  for (let seed = 1; seed <= SEEDS; seed++) {
    const r = rng(1000 + seed);
    // A lock as a random chain leaves it (who is a member, which device signs, which is its person's own).
    const chain: Entry[] = [genesisOf(r)];
    for (let i = 1; i <= 12; i++) {
      const next = nextOf(r, chain.at(-1)!, i);
      try {
        fold([...chain, next], null);
        chain.push(next);
      } catch {}
    }
    const lock = fold(chain, null);
    for (const k of [...signers, ...spare]) assert.deepEqual(signerOf(lock, k.id), oracle.signerOf(lock, k.id), `seed ${seed}: signer`);
    for (let n = 0; n < 10; n++) {
      const cert = certOf(r);
      for (const ever of [false, true]) {
        const want = oracle.certOk(lock, cert, ever);
        assert.equal(certOk(lock, cert, ever), want, `seed ${seed}: cert ${JSON.stringify(cert)}`);
        tally("cert", want);
      }
    }
    // A vault's versions: each tried after the last taken, as kept and as a copy.
    let held: any = null;
    let items: any[] = [];
    for (let n = 0; n < 12; n++) {
      const next = vaultOf(r, held);
      for (const copy of [false, true]) {
        const want = oracle.vaultOk(lock, held, next, copy);
        assert.equal(vaultOk(lock, held, next, copy), want, `seed ${seed}, vault ${n}, copy ${copy}: ${JSON.stringify(next)}`);
        tally("vault", want);
      }
      if (oracle.vaultOk(lock, held, next) === null) held = next;
      if (held === null) continue;
      const prev = items.length && r.int(2) ? r.pick(items) : null;
      const item = itemOf(r, held, prev);
      for (const copy of [false, true]) {
        const want = oracle.itemOk(lock, held, prev, item, copy);
        assert.equal(itemOk(lock, held, prev, item, copy), want, `seed ${seed}, item ${n}, copy ${copy}: ${JSON.stringify(item)}`);
        tally("item", want);
      }
      if (oracle.itemOk(lock, held, prev, item) === null) items = [...items.filter((x) => x.id !== item.id), item];
      const l = listingOf(r) as any;
      if (Array.isArray(l.modes) && Array.isArray(l.hosts)) assert.equal(browserListingOk(l), oracle.browserListingOk(l), `listing ${JSON.stringify(l)}`);
    }
  }
  if (process.env.RULES_TRACE) console.error(JSON.stringify(counts), [...reasons].sort((a, b) => b[1] - a[1]));
  // (both answers tried often, of each: a generator whose records all fail one check would test little)
  for (const [what, [ok, refused]] of Object.entries(counts)) assert.ok(ok! > SEEDS && refused! > SEEDS, `${what}: ${ok} taken, ${refused} refused`);
});
