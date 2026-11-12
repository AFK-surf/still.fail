// The rules' fork choice and workspace list (rules/src/lock/chain.mbt, roster.mbt) against the models they were
// written from, on the worlds the models' own generators draw (rules-fork-check.ts says what is compared). Nothing in
// the product calls these rules yet (2026-11-12): this is what holds them to the design until something does.
//
// RULES_FORK_SEEDS=<n> worlds a variant and family (by default 32 for the workspace lock, 96 for person logs: several
// hundred in all), RULES_FORK_STEPS=<n> steps a world (120). Worker threads as lock-fork-choice.test.ts
// (lock-fork-pool.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { VARIANTS } from "./lock-fork-choice-model.ts";
import { pool, print } from "./lock-fork-pool.ts";
import { V3 } from "./lock-roster-model.ts";
import type { Job, Out } from "./rules-fork-check.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const SEEDS = process.env.RULES_FORK_SEEDS === undefined ? null : Number(process.env.RULES_FORK_SEEDS);
const LOCK_SEEDS = SEEDS ?? 32;
const PERSON_SEEDS = SEEDS ?? 96;
const STEPS = Number(process.env.RULES_FORK_STEPS ?? 120);
/// Seeds a job: small enough that the threads share the work evenly.
const BATCH = 6;

/// What the rules export for this, as rules/js/rules.js is built (without them, no world is run).
const NEW = ["tie_of_js", "fork_before_js", "lock_chain_js", "person_chain_js", "person_fold_ws_js", "roster_js"];
const missing = NEW.filter((f) => typeof (rules as Record<string, unknown>)[f] !== "function");
const FAMILIES = ["free", "faults"] as const;

/// The workspace lock's variants the rules have: one vote a device or by role, the active chain or everything offered,
/// resigning or not; a removal of a device that signs, `tie=signer`.
const LOCK_V = VARIANTS.filter((v) => v.removal === "device" && v.hashfield === "as-is").map((v) => ({ ...v, tie: "signer" as const }));

const jobs = (t: "lock" | "person", vs: Job["v"][], seeds: number): Job[] =>
  vs.flatMap((v) => FAMILIES.flatMap((family) => Array.from({ length: Math.ceil(seeds / BATCH) }, (_, i) =>
    ({ t, v, family, from: 1 + i * BATCH, to: Math.min(seeds, (i + 1) * BATCH), steps: STEPS }) as Job)));

const ask = missing.length > 0 ? null : pool<Job>(new URL("./rules-fork-check.ts", import.meta.url), { rulesFork: true });
const run = (js: Job[]) => (ask === null ? Promise.resolve([] as Out[]) : Promise.all(js.map((j) => ask<Out>(j))));
const lockOut = run(jobs("lock", LOCK_V, LOCK_SEEDS));
const personOut = run(jobs("person", V3, PERSON_SEEDS));

test("the rules export the fork choice and the list", () => {
  assert.deepEqual(missing, [], "rules/js/rules.js lacks these: run rules/build.sh");
});

const sum = (os: Out[]): Out => os.reduce((a, o) => ({
  worlds: a.worlds + o.worlds, checks: a.checks + o.checks, branched: a.branched + o.branched, refusedSeen: a.refusedSeen + o.refusedSeen,
  statements: a.statements + o.statements, differ: [...a.differ, ...o.differ],
}), { worlds: 0, checks: 0, branched: 0, refusedSeen: 0, statements: 0, differ: [] });

test("the rules' active chain of the workspace lock is every model keeper's, at each quarter of a world and at its end", async () => {
  assert.ok(ask !== null, "no rules to compare");
  const o = sum(await lockOut);
  print(`workspace lock: ${o.worlds} worlds (${LOCK_V.length} variants, fault-free and with faults), ${o.checks} chains compared, ${o.branched} children beaten, ${o.refusedSeen} entries refused; ${o.differ.length} differ`);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
  assert.equal(o.differ.length, 0, "the rules and the model differ (the first are printed above)");
  // (branches came up, and forgeries were refused: the comparison was not of straight chains alone)
  assert.ok(o.branched > 0 && o.refusedSeen > 0, `${o.branched} beaten, ${o.refusedSeen} refused`);
});

test("the rules' person-log chains and workspace list are the model's, label for label, with the same reasons", async () => {
  assert.ok(ask !== null, "no rules to compare");
  const o = sum(await personOut);
  print(`person logs: ${o.worlds} worlds (${V3.length} variants, fault-free and with faults), ${o.checks} chains compared, ${o.branched} children beaten, ${o.refusedSeen} entries refused, ${o.statements} statements' reasons; ${o.differ.length} differ`);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
  assert.equal(o.differ.length, 0, "the rules and the model differ (the first are printed above)");
  assert.ok(o.branched > 0 && o.refusedSeen > 0 && o.statements > 0, `${o.branched} beaten, ${o.refusedSeen} refused, ${o.statements} statements`);
});
