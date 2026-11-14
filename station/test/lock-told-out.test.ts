// A device refused at a station's hello where its workspace's chain moved is told what took it out (serve.ts
// `refusalOf`'s `out`, the model's `admitsBefore` as Cloud.givenTo gives it to a station): the removal that took its
// person out, that body's `prev` chain and the entries of the person logs that commit to them, nothing else of the
// workspace; one taken off its person's own log hears it of that log (the refusal's `person`, as before); one the list
// never named is given nothing.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { LockRefusal, endpointBytes, entryHash } from "../src/cloud/lock.ts";
import { wall } from "../src/ops/fibers.ts";
import { refusalOf } from "../src/mesh/serve.ts";
import { WS, bring, dev, ed, handover, station, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// A hello of `d` on endpoint `endpoint`: its base key's proof of the endpoint, as a device's hello carries it.
const helloOf = (d: { base: any }, endpoint: string) => ({ lock: { device: d.base.hex, proof: d.base.sign(endpointBytes(WS, endpoint)) } });

test("a device whose person a removal took out is told that removal and the log entry that commits to it, nothing else", () => {
  const w = world();
  const said = handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const removal = w.bob.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  bring(c, w.bob);
  assert.equal(c.locked()!.state!.members.has("carol"), false, "carol out");
  const endpoint = ed().hex;
  const r = refusalOf(c, helloOf(w.carol.app, endpoint), endpoint, new LockRefusal("refused"), undefined, "carol") as { out?: { bodies: any[]; logs: { genesis: string; entries: any[] }[] } };
  assert.ok(r.out !== undefined, "told");
  assert.deepEqual(r.out.bodies, [removal.body], "the removal alone (its prev chain is itself: bob's first statement)");
  assert.deepEqual(r.out.logs.map((l) => l.genesis), [w.bob.genesis], "bob's log alone");
  const log = r.out.logs[0]!.entries;
  assert.equal(entryHash(log.at(-1)), entryHash(removal.entry), "up to the entry that commits to it");
  assert.equal(log[0].prev, null, "from its genesis");
});

test("a removal said after another statement of its signer: given with its prev chain", () => {
  const w = world();
  const said = handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const before = w.bob.say("station", { key: w.stations[1]!.hex });
  const removal = w.bob.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  bring(c, w.bob);
  const endpoint = ed().hex;
  const r = refusalOf(c, helloOf(w.carol.app, endpoint), endpoint, new LockRefusal("refused"), undefined, "carol") as { out?: { bodies: any[] } };
  assert.deepEqual(new Set(r.out?.bodies.map((b) => b.kind)), new Set(["member.remove", "station"]));
  assert.ok(r.out!.bodies.some((b) => b.salt === before.body.salt) && r.out!.bodies.some((b) => b.salt === removal.body.salt));
  assert.equal(r.out!.bodies.length, 2, "nothing else");
});

test("a device taken off its person's own log hears it of that log, no body; one the list never named is given nothing", () => {
  const w = world();
  handover(w);
  const c = station(w);
  const phone = dev();
  w.carol.add("device", { key: phone.key.id, id: phone.base.hex, label: "phone", sign_key: phone.signer.id });
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  w.carol.add("device.remove", { key: phone.key.id });
  bring(c, w.carol, false);
  const endpoint = ed().hex;
  const r = refusalOf(c, helloOf(phone, endpoint), endpoint, new LockRefusal("refused"), undefined, "carol") as { out?: unknown; person?: { entries: any[] }[] };
  assert.equal(r.out, undefined, "no body");
  assert.ok(r.person?.some((p) => p.entries.at(-1)?.kind === "device.remove"), "its person's log, its removal on");
  const stranger = { signer: ed(), base: ed() };
  const e2 = ed().hex;
  const s = refusalOf(c, helloOf(stranger, e2), e2, new LockRefusal("refused"), undefined, "dan") as { out?: unknown };
  assert.equal(s.out, undefined, "nothing for one never named");
});
