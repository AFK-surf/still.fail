// What reading a workspace's chain costs the rules (rules/src/lock/lock.mbt `fold`), counted, not timed: the map entries
// they copy (`copied_js`). A whole chain folded makes its state once and takes each entry into it, so a chain four times
// as long copies no more for each entry; `apply`, which a station and the fork choice (chain.mbt `active`) call on a
// state they keep, still makes a new state and leaves the one it was given as it was. 2026-11-15: each entry copied the
// whole state, 1.6 s in Node and about 110 s in Hermes for a chain of 1000 members (handover measurements).
import assert from "node:assert/strict";
import { test } from "node:test";
import { type Entry, apply, entryHash, fold, lockChain } from "../src/cloud/lock.ts";
import { ed, signed } from "./lock-moved-world.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const WS = "01HFOLDFOLDFOLDFOLDFOLDFOL";

/// A chain of an owner and `n` members, each member let in by an entry of its own after the genesis.
function chain(n: number): Entry[] {
  const owner = { base: ed(), signer: ed() };
  const body = {
    owner: "o", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "o", email: "o@x", role: "owner" }],
    devices: [{ id: owner.base.hex, sub: "o", kind: "app", label: "o's app", sign_key: owner.signer.id }],
    passkeys: [], stations: [{ key: ed().hex, name: "s0" }], gateways: [],
  };
  const out: Entry[] = [signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">, owner.signer)];
  for (let i = 0; i < n; i++) {
    const last = out[out.length - 1]!;
    out.push(signed({ v: 1, ws: WS, seq: last.seq + 1, prev: entryHash(last), at: 1000, kind: "member", body: { sub: `m${i}`, email: `m${i}@x`, role: "member" } } as Omit<Entry, "sig">, owner.signer));
  }
  return out;
}

/// The map entries the rules copy folding `entries`.
function copiedFolding(entries: Entry[]): number {
  const before: number = rules.copied_js();
  const s = fold(entries, null);
  assert.equal(s.members.size, entries.length, "every member in");
  return rules.copied_js() - before;
}

test("a chain four times as long copies no more for each of its entries", () => {
  const short = chain(100), long = chain(400);
  const a = copiedFolding(short), b = copiedFolding(long);
  console.log(`map entries copied folding 101 entries: ${a} (${(a / short.length).toFixed(1)} an entry); 401 entries: ${b} (${(b / long.length).toFixed(1)} an entry)`);
  assert.ok(b / long.length <= a / short.length, `copies an entry grew with the chain: ${(a / short.length).toFixed(1)} -> ${(b / long.length).toFixed(1)}`);
});

test("apply leaves the state it was given as it was", () => {
  const es = chain(3);
  const s = fold(es.slice(0, 3), null);
  const members = [...s.members.keys()];
  const next = apply(s, es[3]!, null);
  assert.deepEqual([...s.members.keys()], members, "the state given unchanged");
  assert.equal(next.members.size, members.length + 1, "the new one has the member");
  // (and the same entry applied again to it gives the same, as the fork choice does for each child of one parent)
  assert.deepEqual([...apply(s, es[3]!, null).members.keys()], [...next.members.keys()]);
});

/// The map entries the rules copy choosing the active chain of `entries` (the fork choice, chain.mbt `active`).
function copiedChoosing(entries: Entry[]): number {
  const before: number = rules.copied_js();
  const c = lockChain(entries, entryHash(entries[0]!));
  assert.equal(c.hashes.length, entries.length, "every entry on the chain");
  return rules.copied_js() - before;
}

test("the fork choice on a chain without forks, four times as long, copies no more for each of its entries", () => {
  const short = chain(100), long = chain(400);
  const a = copiedChoosing(short), b = copiedChoosing(long);
  console.log(`map entries copied choosing the chain of 101 entries: ${a} (${(a / short.length).toFixed(1)} an entry); 401 entries: ${b} (${(b / long.length).toFixed(1)} an entry)`);
  assert.ok(b / long.length <= a / short.length, `copies an entry grew with the chain: ${(a / short.length).toFixed(1)} -> ${(b / long.length).toFixed(1)}`);
});
