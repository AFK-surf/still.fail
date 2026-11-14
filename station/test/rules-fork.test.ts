// The rules' fork choice, a person's log, a workspace's bodies, list and state (rules/src/lock/chain.mbt, person.mbt,
// body.mbt, roster.mbt, state4.mbt, lock.mbt's `moved`) against the models they were written from, on the worlds the
// models draw (rules-fork-check.ts says what is compared): the workspace lock's first rounds, and the fourth round's
// (lock-roster4-model.ts, 2026-11-13) under its defaults, whose person logs, drawn as round three's were, now carry
// commitments where round three's carried its statements in the clear. Nothing in the product calls these rules but
// the chains (src/cloud/log-keep.ts, 2026-11-12; lock-forks.test.ts holds a station to the model) and the person fold:
// this is what holds them to the design.
//
// RULES_FORK_SEEDS=<n> worlds a variant and family (by default 32 for the workspace lock, 96 for person logs: several
// hundred in all), RULES_FORK_STEPS=<n> steps a world (120), RULES_FORK_SCRIPTED=<n> seeds of the fourth round's
// scripted worlds (6). Worker threads as lock-fork-choice.test.ts (lock-fork-pool.ts).
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { type Entry, endpointProof, entryHash, sigValid, validKeyId } from "../src/cloud/lock.ts";
import { key, signed } from "./lock-world-sim.ts";
import { VARIANTS } from "./lock-fork-choice-model.ts";
import { pool, print } from "./lock-fork-pool.ts";
import { V3 } from "./lock-roster-model.ts";
import type { Job, More, Out } from "./rules-fork-check.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const SEEDS = process.env.RULES_FORK_SEEDS === undefined ? null : Number(process.env.RULES_FORK_SEEDS);
const LOCK_SEEDS = SEEDS ?? 32;
const PERSON_SEEDS = SEEDS ?? 96;
const STEPS = Number(process.env.RULES_FORK_STEPS ?? 120);
const SCRIPTED = Number(process.env.RULES_FORK_SCRIPTED ?? 6);
/// Seeds a job: small enough that the threads share the work evenly.
const BATCH = 6;

/// What the rules export for this, as rules/js/rules.js is built (without them, no world is run).
const NEW = ["tie_of_js", "fork_before_js", "lock_chain_js", "person_chain_js", "person_fold_js", "roster_js", "state4_js", "roster_moved_js", "state4_moved_js", "ws_tag_js", "body_hash_js", "body_refusal_js"];
const missing = NEW.filter((f) => typeof (rules as Record<string, unknown>)[f] !== "function");
const FAMILIES = ["free", "faults"] as const;

/// The workspace lock's variants the rules have: one vote a device or by role, the active chain or everything offered,
/// resigning or not; a removal of a device that signs, `tie=signer`.
const LOCK_V = VARIANTS.filter((v) => v.removal === "device" && v.hashfield === "as-is").map((v) => ({ ...v, tie: "signer" as const }));

const jobs = (t: "lock" | "person", vs: Extract<Job, { t: "lock" | "person" }>["v"][], seeds: number): Job[] =>
  vs.flatMap((v) => FAMILIES.flatMap((family) => Array.from({ length: Math.ceil(seeds / BATCH) }, (_, i) =>
    ({ t, v, family, from: 1 + i * BATCH, to: Math.min(seeds, (i + 1) * BATCH), steps: STEPS }) as Job)));

const ask = missing.length > 0 ? null : pool<Job>(new URL("./rules-fork-check.ts", import.meta.url), { rulesFork: true });
const run = (js: Job[]) => (ask === null ? Promise.resolve([] as Out[]) : Promise.all(js.map((j) => ask<Out>(j))));
const lockOut = run(jobs("lock", LOCK_V, LOCK_SEEDS));
const personOut = run(jobs("person", V3, PERSON_SEEDS));
const scriptedOut = run(Array.from({ length: SCRIPTED }, (_, i) => ({ t: "scripted", from: i + 1, to: i + 1 }) as Job));

test("the rules export the fork choice and the list", () => {
  assert.deepEqual(missing, [], "rules/js/rules.js lacks these: run rules/build.sh");
});

const addMore = (a: More, b: More): More => {
  const refused = { ...a.refused };
  for (const [k, n] of Object.entries(b.refused)) refused[k] = (refused[k] ?? 0) + n;
  const out = { ...a, refused };
  for (const k of Object.keys(a) as (keyof More)[]) if (k !== "refused") (out[k] as number) = (a[k] as number) + (b[k] as number);
  return out;
};
const none: More = { bodies: 0, refused: {}, inForce: 0, lacking: 0, lists: 0, states: 0, off: 0, notOn: 0, webs: 0, old: 0, moved: 0, afterMoved: 0, rolesOther: 0, admitted: 0, removals: 0, toldOut: 0, carried: 0 };
const sum = (os: Out[]): Out => os.reduce((a, o) => ({
  worlds: a.worlds + o.worlds, checks: a.checks + o.checks, branched: a.branched + o.branched, refusedSeen: a.refusedSeen + o.refusedSeen,
  statements: a.statements + o.statements, differ: [...a.differ, ...o.differ], more: addMore(a.more, o.more),
}), { worlds: 0, checks: 0, branched: 0, refusedSeen: 0, statements: 0, differ: [], more: none });
const said = (r: Record<string, number>) => Object.entries(r).map(([k, n]) => `${k}: ${n}`).join("; ") || "none";
const told = (o: Out) => {
  const m = o.more;
  print(`  bodies offered ${m.bodies}, refused ${Object.values(m.refused).reduce((a, b) => a + b, 0)} (${said(m.refused)}); statements in force ${m.inForce}, entries lacking their body ${m.lacking}; lists ${m.lists}, states ${m.states} (off ${m.off}, not on ${m.notOn}); web devices ${m.webs}; old chains ${m.old}, moved ${m.moved}, an entry after it refused ${m.afterMoved}, chosen otherwise by votes by role ${m.rolesOther}; devices of a state let in by admit ${m.admitted}; removals compared ${m.removals}, holders a removal took out told ${m.toldOut}; states of a chain carried (D6) ${m.carried}`);
};

test("the rules' active chain of the workspace lock is every model keeper's, at each quarter of a world and at its end", async () => {
  assert.ok(ask !== null, "no rules to compare");
  const o = sum(await lockOut);
  print(`workspace lock: ${o.worlds} worlds (${LOCK_V.length} variants, fault-free and with faults), ${o.checks} chains compared, ${o.branched} children beaten, ${o.refusedSeen} entries refused; ${o.differ.length} differ`);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
  assert.equal(o.differ.length, 0, "the rules and the model differ (the first are printed above)");
  // (branches came up, and forgeries were refused: the comparison was not of straight chains alone)
  assert.ok(o.branched > 0 && o.refusedSeen > 0, `${o.branched} beaten, ${o.refusedSeen} refused`);
});

test("the rules' person logs, bodies, lists and states are the fourth round's model's on its drawn worlds, label for label, with the same reasons", async () => {
  assert.ok(ask !== null, "no rules to compare");
  const o = sum(await personOut);
  print(`person logs and a workspace, drawn: ${o.worlds} worlds (${V3.length} variants, fault-free and with faults; as drawn, one body held back for good, two workspaces), ${o.checks} chains compared, ${o.branched} children beaten, ${o.refusedSeen} entries refused, ${o.statements} statements' reasons; ${o.differ.length} differ`);
  told(o);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
  assert.equal(o.differ.length, 0, "the rules and the model differ (the first are printed above)");
  // (forks came up and forgeries were refused, bodies were refused, some lacked, statements had reasons: not trivial worlds)
  const m = o.more;
  assert.ok(o.branched > 0 && o.refusedSeen > 0 && o.statements > 0 && Object.keys(m.refused).length > 0 && m.lacking > 0 && m.inForce > 0 && m.admitted > 0 && m.removals > 0 && m.toldOut > 0, `${o.branched} beaten, ${o.refusedSeen} refused, ${o.statements} statements, ${m.lacking} lacking, ${m.removals} removals, ${m.toldOut} told out`);
});

test("the rules are the fourth round's model's on its scripted worlds: bodies no one's, web devices by a keeper's clock, a revoked key, off and on again, the handover, the handover that waits for nobody", async () => {
  assert.ok(ask !== null, "no rules to compare");
  const o = sum(await scriptedOut);
  print(`person logs and a workspace, scripted: ${o.worlds} seeds of M2, M5, a revoked key's web device and off, M6, M7's four rows, M8's two, ${o.checks} chains compared, ${o.branched} children beaten, ${o.refusedSeen} entries refused, ${o.statements} statements' reasons; ${o.differ.length} differ`);
  told(o);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
  assert.equal(o.differ.length, 0, "the rules and the model differ (the first are printed above)");
  const m = o.more;
  assert.ok(m.off > 0 && m.moved > 0 && m.carried > 0 && m.afterMoved === m.moved && m.webs > 0 && o.branched > 0 && Object.keys(m.refused).length >= 5, `off ${m.off}, moved ${m.moved}, after it refused ${m.afterMoved}, web devices ${m.webs}, ${o.branched} beaten, ${Object.keys(m.refused).length} reasons a body was refused`);
});

// A device has three keys: its base key (`id`), its key on its person's log (`key`, sealed for the person's presence:
// it signs that log alone) and the key it signs a workspace's things with, unasked (a vault's versions and box
// certificates; a workspace chain's entries), which its log's entries say as `sign_key` (client/core-ts/src/
// personal-lock.ts `Device`). The fold keeps the last said and every one said; a moved workspace's state names a
// device by it, never by the log's key (the lead, 2026-11-13: nothing the workspace signer signed checked out against
// the moved state).
test("a person's log says each device's signer: the fold keeps it and those said before, and a moved workspace's state names the device by it, never by its key on the log", () => {
  const crypto = { sha256Hex: (s: string) => createHash("sha256").update(s).digest("hex"), sigValid, validKeyId, endpointProof };
  const [log1, log2, log3] = [key(7101), key(7102), key(7103)];
  const [s1, s2a, s2b] = [key(7201), key(7202), key(7203)];
  const [id1, id2, id3] = [key(7301).hex, key(7302).hex, key(7303).hex];
  const chain: Entry[] = [];
  const add = (kind: string, body: unknown) => {
    const last = chain.at(-1);
    chain.push(signed({ v: 1, ws: "person:alice", seq: chain.length, prev: last ? entryHash(last) : null, at: 1_790_000_000, kind, body } as Omit<Entry, "sig">, log1));
  };
  add("genesis", { sub: "alice", device: { key: log1.id, id: id1, label: "app", sign_key: s1.id } });
  add("device", { key: log2.id, id: id2, label: "phone", sign_key: s2a.id });
  // (said again with another signer: that device's signer the one said now, the one before kept)
  add("device", { key: log2.id, id: id2, label: "phone", sign_key: s2b.id });
  // (one that says none, and one that says what is no ed25519 key id: none, never a refusal)
  add("device", { key: log3.id, id: id3, label: "old app" });
  const p = rules.person_fold_js(chain, "alice", crypto) as any;
  assert.ok(!("error" in p), JSON.stringify(p));
  const byId = new Map((p.devices as any[]).map((d) => [d.id, d]));
  assert.deepEqual([id1, id2, id3].map((id) => [byId.get(id)?.sign_key ?? null, byId.get(id)?.sign_keys]), [[s1.id, [s1.id]], [s2b.id, [s2a.id, s2b.id]], [null, []]], "the fold keeps each device's signer");
  const bad = [...chain];
  const last = bad.at(-1)!;
  bad.push(signed({ v: 1, ws: "person:alice", seq: bad.length, prev: entryHash(last), at: 1_790_000_000, kind: "device", body: { key: log3.id, id: id3, label: "old app", sign_key: "p256:x" } } as Omit<Entry, "sig">, log1));
  const q = rules.person_fold_js(bad, "alice", crypto) as any;
  assert.ok(!("error" in q), "a signer that is no key id is none, never a refusal");
  assert.equal((q.devices as any[]).find((d) => d.id === id3)?.sign_key, undefined);
  // The workspace said in alice's log (her `open`): its state names each app by its signer.
  const g = entryHash(chain[0]!);
  const open = { ws: "ws", kind: "open", origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: {}, email: "a@x.com", prev: null, salt: "77".repeat(16) };
  add("ws", { t: rules.ws_tag_js("ws", g, crypto), h: rules.body_hash_js(open, crypto) });
  const out = rules.state4_js("ws", g, [chain], [open], 1_790_000_100, crypto) as any;
  assert.equal(out.on, "on", JSON.stringify(out.error ?? out.on));
  const devs = new Map((out.state.devices as [string, any][]).map(([id, d]) => [id, d]));
  const keys = new Map(out.state.signKeys as [string, string[]][]);
  assert.deepEqual([id1, id2, id3].map((id) => [devs.get(id)?.kind, devs.get(id)?.sign_key ?? null, keys.get(id) ?? []]), [["app", s1.id, [s1.id]], ["app", s2b.id, [s2a.id, s2b.id]], ["app", null, []]], "named by its signer");
  const logKeys = new Set([log1.id, log2.id, log3.id]);
  assert.ok([...devs.values()].every((d) => !logKeys.has(d.sign_key)) && [...keys.values()].flat().every((k) => !logKeys.has(k)), "never by its key on the log");
  // The signer alone signs as the device: `signer_js` finds the app by it, and by its key on the log nothing.
  assert.equal(rules.signer_js(out.rules, s1.id, null)?.sub, "alice");
  assert.equal(rules.signer_js(out.rules, log1.id, null), null);
  assert.equal(rules.signer_js(out.rules, s2a.id, null), null, "a signer said before signs no more");
});
