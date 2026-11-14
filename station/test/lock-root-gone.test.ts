// A moved workspace whose root's person is gone (their devices lost, or another owner wanting them out), on the
// station's own code: what the state in force does with it (rules/src/lock/roster.mbt: the root's pair always stands as
// owner and its binding never moves; on and off are said in the root's log alone), and what `stillfail lock reset`
// (Cloud.resetLock) leaves a station of two. What is so on 2026-11-14, held as found: nothing here is a design.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { LockRefusal } from "../src/cloud/lock.ts";
import { Cloud } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { inLock, inLockBringing } from "../src/mesh/serve.ts";
import { Log, bring, dev, handover, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

const as = (sub: string, d: { signer: any; base: any }, role = "member") => ({ viewer: viewerOf(sub, d, role), exp: NOW + 10 * 86400, iat: NOW, sid: "s" });
const roleOf = (c: Cloud, sub: string) => c.locked()?.state?.members.get(sub)?.role ?? null;

/// alice the root, bob made an owner by her, carol a member; both stations given every log.
function setUp() {
  const w = world();
  handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  const c = [station(w, 0), station(w, 1)];
  for (const s of c) for (const l of [w.alice, w.bob, w.carol]) bring(s, l);
  return { w, c };
}

test("another owner cannot take the root's person out nor lower them: they stay the owner, by their log", () => {
  const { w, c } = setUp();
  assert.equal(roleOf(c[0]!, "bob"), "owner");
  // (alice has no admit to cancel: a removal of her cancels nothing)
  w.bob.say("member.remove", { sub: "alice", cancels: [] });
  w.bob.say("member", { sub: "alice", email: "alice@x", lock: w.alice.genesis, role: "member" });
  bring(c[0]!, w.bob);
  assert.equal(roleOf(c[0]!, "alice"), "owner", "still the owner");
  const a = as("alice", w.alice.app, "owner");
  assert.equal(inLock(c[0]!, a, "owner", a.viewer.device).viewer.role, "owner", "her app still let in");
  // and only her log turns it off: bob's off is no one's
  w.bob.say("off", {});
  bring(c[0]!, w.bob);
  assert.notEqual(c[0]!.locked(), null, "still on");
});

test("the root's person begun anew (every device lost, a new log): another owner's admit of the new log binds nothing; its app is refused, its off counts for nothing; the old log still roots it", () => {
  const { w, c } = setUp();
  const again = new Log("alice", dev());
  w.bob.say("member", { sub: "alice", email: "alice@x", lock: again.genesis, role: "owner" });
  bring(c[0]!, w.bob);
  again.say("off", {});
  bring(c[0]!, again);
  const m = c[0]!.locked()?.state?.members.get("alice");
  assert.equal(m?.role, "owner");
  assert.equal(c[0]!.locked()?.state?.persons.get("alice"), w.alice.genesis, "bound by her lost log still");
  assert.notEqual(c[0]!.locked(), null, "the new log's off: still on");
  const n = as("alice", again.app, "owner");
  assert.throws(() => inLockBringing(c[0]!, n, "owner", n.viewer.device, { lock: { person: again.entries } }), LockRefusal, "her new app refused");
});

test("`stillfail lock reset` on one station of two: that one lets in whoever the control plane's credential names, a device on no log too; the other refuses it still", () => {
  const { c } = setUp();
  const stranger = dev();
  const s = as("carol", stranger);
  assert.throws(() => inLock(c[0]!, s, "member", s.viewer.device), LockRefusal, "before: refused");
  assert.equal(Cloud.resetLock(c[0]!.data), true);
  const reset = new Cloud(c[0]!.data, false);
  assert.equal(reset.chain(), null, "no chain pinned");
  assert.equal(reset.locked(), null, "nothing in force");
  assert.equal(inLock(reset, s, "member", s.viewer.device).viewer.role, "member", "a device on no log let in, by the credential alone");
  assert.equal(inLock(reset, s, "owner", s.viewer.device).viewer.role, "owner", "with the role the credential says");
  assert.throws(() => inLock(c[1]!, s, "member", s.viewer.device), LockRefusal, "the other station refuses it still");
});
