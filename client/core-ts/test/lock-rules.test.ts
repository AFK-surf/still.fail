// The device checks the workspace's lock by the stations' own rules (rules/, MoonBit; vault/lock-check.ts gives them
// the device's cryptography, @noble's): on station/test/lock-chains.ts's seeded random chains, every prefix is taken or
// refused as the TypeScript rules the stations had did (station/test/lock-oracle.ts, node's cryptography), with the
// same words, the same devices, passkeys and members, and the same signer for each key; signed by Ed25519 and P-256
// app keys and by passkeys, so @noble's checks of each are node's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { checkLock, signerIn } from "../src/vault/lock-check.ts";
import { genesisOf, nextOf, p256s, passkeys, rng, signers, spare } from "../../../station/test/lock-chains.ts";
import { fold, signer } from "../../../station/test/lock-oracle.ts";
import type { Entry } from "../../../station/src/cloud/lock.ts";

const SEEDS = Number(process.env.RULES_SEEDS ?? 20);
const NOW = 1000 + 20 * 60;

function stations(entries: Entry[]) {
  try {
    const s = fold(entries, NOW);
    return {
      head: s.head, genesis: s.genesis, disabled: s.disabled, cloudKeys: s.cloud_keys,
      members: [...s.members].map(([sub, m]) => [sub, m.role]),
      devices: [...s.devices].map(([id, d]) => [id, { id: d.id, sub: d.sub, kind: d.kind, sign_key: d.sign_key, exp: d.exp, by: d.by, own: d.own }]),
      passkeys: [...s.passkeys].map(([k, p]) => [k, { sub: p.sub, own: p.own }]),
      signed: [...s.signed],
      signers: [...signers, ...spare, ...p256s, ...passkeys].map((k) => signer(s, { key: k.id }, NOW)),
    };
  } catch (e) {
    return { error: `the workspace's lock does not check out: ${(e as Error).message}` };
  }
}

function device(entries: Entry[]) {
  try {
    const s = checkLock(entries as Parameters<typeof checkLock>[0], NOW);
    return {
      head: s.head, genesis: s.genesis, disabled: s.disabled, cloudKeys: s.cloudKeys,
      members: [...s.members],
      devices: [...s.devices].map(([id, d]) => [id, { id: d.id, sub: d.sub, kind: d.kind, sign_key: d.sign_key, exp: d.exp, by: d.by, own: d.own }]),
      passkeys: [...s.passkeys],
      signed: [...s.signed],
      signers: [...signers, ...spare, ...p256s, ...passkeys].map((k) => signerIn(s, k.id, NOW)),
    };
  } catch (e) {
    return { error: (e as Error).message };
  }
}

test("the device takes and refuses each random chain's every prefix as the stations' TypeScript rules did", () => {
  let taken = 0, refused = 0;
  const byAlg = new Map<string, number>();
  for (let seed = 1; seed <= SEEDS; seed++) {
    const r = rng(seed);
    const kept: Entry[] = [genesisOf(r)];
    for (let i = 1; i <= 30; i++) {
      const next = nextOf(r, kept.at(-1)!, i);
      const tried = [...kept, next];
      const want = stations(tried);
      assert.deepEqual(JSON.parse(JSON.stringify(device(tried))), JSON.parse(JSON.stringify(want)), `seed ${seed}, entry ${i} (${next.kind})`);
      if ("error" in want) refused++;
      else {
        kept.push(next);
        taken++;
        byAlg.set(next.sig.alg, (byAlg.get(next.sig.alg) ?? 0) + 1);
      }
    }
  }
  assert.ok(taken > SEEDS * 5 && refused > SEEDS * 5, `${taken} taken, ${refused} refused`);
  // (taken signed each way a device signs: an app's Ed25519 or P-256 key, a passkey)
  for (const alg of ["Ed25519", "ES256", "webauthn"]) assert.ok((byAlg.get(alg) ?? 0) > SEEDS / 4, `${alg}: ${JSON.stringify([...byAlg])}`);
});
