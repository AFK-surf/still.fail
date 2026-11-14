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
import { type Entry, entryHash, state4Moved } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { inLock } from "../src/mesh/serve.ts";
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

test("two bindings of one member to two logs: the one of the smaller entry hash, whatever the order the logs and bodies come in (the rules, as every keeper reads them; a station keeps one log a person)", () => {
  const w = boundWorld();
  const other = new Log("bob", w.bob.app);
  const a = bind(w, w.bob), b = bind(w, other);
  const want = entryHash(a.entry) < entryHash(b.entry) ? w.bob.genesis : other.genesis;
  const bodies = [...[w.alice, w.bob, other].flatMap((l) => [...l.bodies.values()])];
  for (const order of [[w.bob, other], [other, w.bob]]) {
    const s = state4Moved(WS, w.chain, [w.alice, w.carol, ...order].map((l) => l.entries), order[0] === w.bob ? bodies : [...bodies].reverse(), NOW);
    assert.equal(s.state.persons.get("bob"), want);
  }
});
