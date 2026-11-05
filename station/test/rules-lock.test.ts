// The workspace lock's rules as rules/ (MoonBit) has them, as station/src/cloud/lock.ts calls them, against the
// TypeScript they replaced (lock-oracle.ts): on
// seeded random chains (each entry of a random kind, its body well formed or not, signed by a key in the lock or not,
// following the head or not), every prefix folds to the same state or is refused with the same words, and each device
// is let in or turned away the same. The cryptography is the stations' own on both sides.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { type Entry, type LockState, admit as stationAdmit, endpointBytes, endpointProof, entryHash, fold as stationFold, signedBytes, sigValid, validKeyId } from "../src/cloud/lock.ts";
import { WS, bases, genesisOf, nextOf, people, rng, spare } from "./lock-chains.ts";
import { admit, fold } from "./lock-oracle.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const crypto = {
  sha256Hex: (s: string) => createHash("sha256").update(s).digest("hex"),
  sigValid, validKeyId, endpointProof,
};

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
