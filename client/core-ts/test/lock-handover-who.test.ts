// Who hands a workspace's chain over by itself (src/lock-handover.ts `mayHandOver`, `genesisPerson`; the owner,
// 2026-11-14): the person who turned safe mode on (whose device signed the genesis) while an owner; another owner once
// 14 days passed from the later of the switch and the genesis, or at once where that person is no owner any more;
// nobody but an owner; nobody on a chain moved. Each branch alone, of chains made here (what is checked is the chain's
// fold: the signatures are the plan's, test/lock-handover.test.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { type Entry, entryHash, next } from "../src/lock.ts";
import { HAND_OVER_FIRST_SECS, genesisPerson, mayHandOver } from "../src/lock-handover.ts";

const DAY = 86400;
const AT = 1_790_000_000;
const sig = (key: string) => ({ key, alg: "Ed25519", sig: "" });

/// A chain: s0 and s1 owners, r2 an admin; the genesis signed by `by` (s0's device's key, K0, by default).
function chain(o: { by?: string; owner?: string; more?: [string, unknown][] } = {}): Entry[] {
  const g = { ...next("ws", null, AT, "genesis", {
    owner: o.owner ?? "s0",
    members: [{ sub: "s0", email: "a@x", role: "owner" }, { sub: "s1", email: "b@x", role: "owner" }, { sub: "r2", email: "c@x", role: "admin" }],
    devices: [{ id: "d0", sub: "s0", kind: "app", label: "", sign_key: "K0" }, { id: "d1", sub: "s1", kind: "app", label: "", sign_key: "K1" }],
    stations: [], passkeys: [], gateways: [], origins: [], rp_id: "x", cloud_keys: [],
  }), sig: sig(o.by ?? "K0") } as Entry;
  const out: Entry[] = [g];
  for (const [kind, body] of o.more ?? []) {
    const last = out[out.length - 1]!;
    out.push({ ...next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(g) }, AT, kind, body), sig: sig("K1") } as Entry);
  }
  return out;
}

test("the genesis's person: the device the genesis names by the key that signed it; else its owner", () => {
  assert.equal(genesisPerson(chain()), "s0");
  assert.equal(genesisPerson(chain({ by: "K1", owner: "s0" })), "s1", "by the signer, not the body's owner");
  assert.equal(genesisPerson(chain({ by: "KX", owner: "s0" })), "s0", "no device by that key: the owner");
  assert.equal(genesisPerson([]), null);
});

test("the genesis's person hands over at once; another owner only 14 days on from the later of the switch and the genesis", () => {
  const c = chain();
  assert.equal(mayHandOver(c, "s0", 0, AT), true);
  assert.equal(mayHandOver(c, "s1", 0, AT + HAND_OVER_FIRST_SECS - 1), false);
  assert.equal(mayHandOver(c, "s1", 0, AT + HAND_OVER_FIRST_SECS), true);
  assert.equal(HAND_OVER_FIRST_SECS, 14 * DAY);
  // (the switch later than the genesis: from the switch)
  assert.equal(mayHandOver(c, "s1", AT + 30 * DAY, AT + 40 * DAY), false);
  assert.equal(mayHandOver(c, "s1", AT + 30 * DAY, AT + 44 * DAY), true);
});

test("another owner at once where the genesis's person is no owner: made an admin, or taken out", () => {
  const lowered = chain({ more: [["member", { sub: "s0", email: "a@x", role: "admin" }]] });
  assert.equal(mayHandOver(lowered, "s1", 0, AT), true);
  assert.equal(mayHandOver(lowered, "s0", 0, AT), false, "no owner: not theirs");
  const out = chain({ more: [["member.remove", { sub: "s0" }]] });
  assert.equal(mayHandOver(out, "s1", 0, AT), true);
});

test("nobody but an owner, and nobody on a chain moved", () => {
  assert.equal(mayHandOver(chain(), "r2", 0, AT + 100 * DAY), false, "an admin");
  assert.equal(mayHandOver(chain(), "r9", 0, AT + 100 * DAY), false, "no member");
  const moved = chain({ more: [["moved", { root: "f".repeat(64) }]] });
  assert.equal(mayHandOver(moved, "s0", 0, AT), false);
  assert.equal(mayHandOver([], "s0", 0, AT), false);
});
