// A member the chain as it moved bound to no log binds themselves to their own log (the lead, 2026-11-14: a carried
// member with no log of their own does for themselves what they did before the move): `bind {key, sig}` said in that
// log, proved by the signer the chain names for an own app device of theirs over the workspace, the member, the log and
// the move (rules/src/lock/roster.mbt `binds_of`, `bind_form` under `bind_tag`). It counts as the chain's admit of them
// to that log: their log's devices come in, what the chain carried of theirs stays; a removal of them takes it back.
// Nothing else binds: the public `sign_key` a log says, a proof for another workspace or another log, a signer the
// chain took off or names as nobody's of theirs, a binding after their removal.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { type Entry, type LockState, entryHash, state4Moved } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { inLock } from "../src/mesh/serve.ts";
import { TAG, certOk, newBoxPair, signedBytes } from "../src/vault/crypto.ts";
import { bindBytes } from "./lock-roster4-model.ts";
import { type Dev, type Key, Log, WS, WS2, bring, dev, signed, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);
const as = (sub: string, d: { base: Key }, role = "member") => ({ viewer: viewerOf(sub, d, role), exp: NOW + 10 * 86400, iat: NOW, sid: "s" });

/// The world of lock-moved-world.ts with alice bound to her log on the chain (as the device that moves a chain always
/// is: views/lock.ts `handOverPlan`), and, before its `moved`, what `before` signs on the chain (by alice's app); bob and
/// carol bound to no log.
function boundWorld(before: (w: ReturnType<typeof world>, add: (kind: string, body: unknown, by?: Key) => void) => void = () => {}) {
  const w = world();
  const chain: Entry[] = [w.first];
  const add = (kind: string, body: unknown, by: Key = w.alice.app.signer) => {
    const head = chain.at(-1)!;
    chain.push(signed({ v: 1, ws: w.ws, seq: head.seq + 1, prev: entryHash(head), at: 1000, kind, body }, by));
  };
  add("person", { sub: "alice", person: w.alice.genesis });
  before(w, add);
  add("moved", { root: w.alice.genesis });
  return { ...w, chain, moved: chain.at(-1)! };
}

function stationOf(w: ReturnType<typeof boundWorld>): Cloud {
  const data = mkdtempSync(join(tmpdir(), "lock-bind-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[0]!.hex, workspace: w.ws, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s, j) => ({ id: s.hex, name: `s${j}` })), revocations: [],
  });
  const c = new Cloud(data, false);
  c.takeLock(w.chain.slice(0, -1));
  c.takeLock(w.chain, null, true);
  return c;
}

/// `l`'s binding, proved by `by` (their app's signer by default) for workspace `ws`, log `log` and the world's move.
const bind = (w: ReturnType<typeof boundWorld>, l: Log, o: { by?: Key; ws?: string; log?: string; sig?: string } = {}) => {
  const by = o.by ?? l.app.signer;
  const sig = o.sig ?? by.sign(bindBytes(o.ws ?? WS, l.sub, o.log ?? l.genesis, entryHash(w.moved)));
  return l.say("bind", { key: by.id, sig });
};
/// A second app device on `l`'s log (its key there, its signer, its base).
const phoneOn = (l: Log): Dev => {
  const p = dev();
  l.add("device", { key: p.key.id, id: p.base.hex, label: `${l.sub}'s phone`, sign_key: p.signer.id });
  return p;
};
const stateOf = (c: Cloud) => c.locked()!.state!;

test("a member the chain bound to no log binds themselves by their own app's proof: bound to their log, its devices in, the chain's of theirs still in, in the role the chain gives them", () => {
  const w = boundWorld();
  const c = stationOf(w);
  const phone = phoneOn(w.bob);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.equal(stateOf(c).persons.has("bob"), false, "carried, bound to no log");
  assert.equal(stateOf(c).devices.has(phone.base.hex), false, "a device of an unbound log: not in");
  assert.equal(stateOf(c).devices.get(w.bob.app.base.hex)?.by, "chain");
  bind(w, w.bob);
  bring(c, w.bob);
  const s = stateOf(c);
  assert.equal(s.persons.get("bob"), w.bob.genesis, "bound to his log by his own proof");
  assert.equal(s.members.get("bob")?.role, "admin", "the chain's role");
  assert.equal(s.devices.get(phone.base.hex)?.sign_key, phone.signer.id, "his log's device in");
  assert.ok(s.devices.has(w.bob.app.base.hex), "his app in");
  const p = as("bob", phone, "admin");
  assert.equal(inLock(c, p as never, "admin", p.viewer.device).viewer.role, "admin", "let in by the station");
  assert.equal(s.persons.has("carol"), false, "carol still bound to none");
});

test("nothing else binds: the log's public sign_key with no proof, a proof for another workspace or another log, by a signer the chain names as nobody's of theirs or took off, a binding after their removal", () => {
  const cases: [string, (w: ReturnType<typeof boundWorld>, c: Cloud) => void, ((w: ReturnType<typeof world>, add: (kind: string, body: unknown, by?: Key) => void) => void)?][] = [
    ["no proof (the public sign_key, a signature of nothing)", (w) => void bind(w, w.bob, { sig: "00".repeat(64) })],
    ["a proof for another workspace", (w) => void bind(w, w.bob, { ws: WS2 })],
    ["a proof for another log", (w) => void bind(w, w.bob, { log: w.carol.genesis })],
    ["a signer the chain names as another's own (alice's)", (w) => void bind(w, w.bob, { by: w.alice.app.signer })],
    ["a signer the chain took off", (w) => void bind(w, w.bob, { by: gone })],
    ["after their removal", (w, c) => {
      w.alice.say("member.remove", { sub: "bob", cancels: [entryHash(w.moved)] });
      bring(c, w.alice);
      assert.equal(stateOf(c).members.has("bob"), false, "out");
      bind(w, w.bob);
    }],
  ];
  // (a phone of bob's on the chain, put in by his app and taken off it before the move)
  let gone: Key = dev().signer;
  const withGone = (w: ReturnType<typeof world>, add: (kind: string, body: unknown, by?: Key) => void) => {
    const p = dev();
    gone = p.signer;
    add("device", { id: p.base.hex, sub: "bob", kind: "app", label: "bob's phone", sign_key: p.signer.id }, w.bob.app.signer);
    add("device.remove", { id: p.base.hex }, w.bob.app.signer);
  };
  for (const [what, act] of cases) {
    const w = boundWorld(what.startsWith("a signer the chain took off") ? withGone : undefined);
    const c = stationOf(w);
    const phone = phoneOn(w.bob);
    for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
    act(w, c);
    bring(c, w.bob);
    const s = stateOf(c);
    assert.notEqual(s.persons.get("bob"), w.bob.genesis, `${what}: not bound`);
    assert.equal(s.devices.has(phone.base.hex), false, `${what}: his log's device not in`);
  }
});

// ── two bindings of one member (the lead's review, 2026-11-14) ─────────────────────────────────────────────────────
// Settled by what the signer cannot choose, the smaller signer key (an entry hash is ground at will by whoever makes
// the log), and never for a log proved by a device another binding's log took off: such a binding is attacked by it,
// and the grounded extension decides, as the list does for removals (rules/src/lock/roster.mbt `binds_of`). Where each
// took the other's device off, no binding, and none of the devices any of them took off carried.

/// The world with bob's app A, his phone X and his laptop B on the chain as his own (put in by his app); `smaller`:
/// X's signer key the smaller of A's and X's, or the larger.
function rivalWorld(smaller: "X" | "A") {
  let X!: Dev, B!: Dev;
  const w = boundWorld((w, add) => {
    do X = dev();
    while ((X.signer.id < w.bob.app.signer.id) !== (smaller === "X"));
    B = dev();
    add("device", { id: X.base.hex, sub: "bob", kind: "app", label: "bob's phone", sign_key: X.signer.id }, w.bob.app.signer);
    add("device", { id: B.base.hex, sub: "bob", kind: "app", label: "bob's laptop", sign_key: B.signer.id }, w.bob.app.signer);
  });
  return { ...w, A: w.bob.app, X, B };
}
type Rivals = ReturnType<typeof rivalWorld>;
/// A chain device of bob's taken off his log `l` by `by` (a key on it), as `removeCarried` does: put on under a key made
/// and thrown away, then that key taken off.
const takeOff = (l: Log, d: Dev, by: Key = l.app.key) => {
  const thrown = dev().key;
  l.add("device", { key: thrown.id, id: d.base.hex, label: "lost", sign_key: thrown.id }, by);
  l.add("device.remove", { key: thrown.id }, by);
};
/// L2, a log X begins and binds, its binding's entry hash smaller (`smaller`) or larger than `than`'s; `more`, what
/// else it says after.
function second(w: Rivals, than: { entry: Entry }, smaller: boolean, more: (l: Log) => void = () => {}): Log {
  for (;;) {
    const l = new Log("bob", w.X);
    const b = bind(w, l);
    if ((entryHash(b.entry) < entryHash(than.entry)) === smaller) {
      more(l);
      return l;
    }
  }
}
/// The state as every keeper of these logs reads it, the logs and bodies in either order: one state, or the test fails.
function read(w: Rivals, logs: Log[]) {
  const bodies = [w.alice, w.carol, ...logs].flatMap((l) => [...l.bodies.values()]);
  const states = [logs, [...logs].reverse()].map((ls, i) => state4Moved(WS, w.chain, [w.alice, w.carol, ...ls].map((l) => l.entries), i === 0 ? bodies : [...bodies].reverse(), NOW).state);
  assert.deepEqual(states[1], states[0], "every reader the same state");
  return states[0]!;
}
/// Whether a vault's key may be sealed to device `d` on the state (a box certificate signed by its signer).
const sealable = (s: LockState, d: Dev) => {
  const cert = { v: 1 as const, ws: WS, device: d.base.hex, box: newBoxPair().pub, at: NOW };
  return certOk(s, { ...cert, sig: { key: d.signer.id, alg: "Ed25519", sig: d.signer.sign(signedBytes(cert, TAG.box)) } }) === null;
};

test("two bindings (i): the phone bob took off binds a log of its own, its binding's entry hash and its key the smaller: bob stays bound to his log, the phone not in", () => {
  const w = rivalWorld("X");
  const a = bind(w, w.bob);
  takeOff(w.bob, w.X);
  const L2 = second(w, a, true);
  const s = read(w, [w.bob, L2]);
  assert.equal(s.persons.get("bob"), w.bob.genesis, "bound to the log that took the phone off, not to the phone's");
  assert.equal(s.devices.has(w.X.base.hex), false, "the phone taken off: not in");
  assert.ok(s.devices.has(w.A.base.hex) && s.devices.has(w.B.base.hex), "his app and his laptop in");
});

test("two bindings (ii): each took the other's device off: no binding, neither device carried, the one neither touched carried, nothing of the phone's log in, no vault key sealed to them", () => {
  const w = rivalWorld("X");
  const a = bind(w, w.bob);
  takeOff(w.bob, w.X);
  let P!: Dev;
  const L2 = second(w, a, true, (l) => {
    takeOff(l, w.A);
    P = phoneOn(l);
  });
  const s = read(w, [w.bob, L2]);
  assert.equal(s.members.get("bob")?.role, "admin", "a member still, as the chain carries him");
  assert.equal(s.persons.has("bob"), false, "bound to no log");
  for (const [d, what] of [[w.X, "the phone"], [w.A, "the app"], [P, "a device of the phone's log"]] as const) {
    assert.equal(s.devices.has(d.base.hex), false, `${what}: not in`);
    assert.equal(sealable(s, d), false, `${what}: no vault key sealed to it`);
  }
  assert.equal(s.devices.get(w.B.base.hex)?.by, "chain", "the laptop, taken off by neither, carried");
  assert.equal(sealable(s, w.B), true, "the laptop sealed to as before");
});

test("two bindings (iii): two honest ones, neither taking anything off: the one of the smaller signer key, whatever the entry hashes, for every reader", () => {
  for (const smaller of ["X", "A"] as const) {
    const w = rivalWorld(smaller);
    const a = bind(w, w.bob);
    // (the smaller key's binding the larger entry hash: the old rule chose the other)
    const L2 = second(w, a, smaller === "A");
    const s = read(w, [w.bob, L2]);
    assert.equal(s.persons.get("bob"), smaller === "X" ? L2.genesis : w.bob.genesis, `the smaller key's (${smaller}'s) log`);
    for (const d of [w.A, w.X, w.B]) assert.ok(s.devices.has(d.base.hex), "each of his devices in");
  }
});

test("two bindings (iv): bob's log later takes off the very app that proved its binding, by his laptop: still bound to it, the app not in, and the phone it took off binds nothing", () => {
  const w = rivalWorld("X");
  const a = bind(w, w.bob);
  takeOff(w.bob, w.X);
  w.bob.add("device", { key: w.B.key.id, id: w.B.base.hex, label: "bob's laptop", sign_key: w.B.signer.id });
  w.bob.add("device.remove", { key: w.A.key.id }, w.B.key);
  const L2 = second(w, a, true);
  const s = read(w, [w.bob, L2]);
  assert.equal(s.persons.get("bob"), w.bob.genesis, "still bound to his log");
  assert.equal(s.devices.has(w.A.base.hex), false, "the app it took off: not in");
  assert.equal(s.devices.has(w.X.base.hex), false, "the phone it took off: not in");
  assert.equal(s.devices.get(w.B.base.hex)?.sign_key, w.B.signer.id, "the laptop, on his log, in");
});
