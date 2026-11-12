// The fourth round of the lock's model (lock-roster4-model.ts, 2026-11-13): statements of a workspace as commitments in
// its people's logs with bodies kept apart, web devices in a person's own log, the settings and turning off said by the
// root, one state out of it, the handover from a workspace's own chain. What holds of M1-M7 is measured and printed;
// nothing here asserts that the design keeps a property. What is asserted is the model's own soundness: its person-log
// rules say what `personFold` says on the product's kinds, no keeper stores what a relay forged, the state worked out
// from the bodies a keeper keeps is the state worked out from every body made wherever it lacks none, every keeper's
// old chain is the product's `fold` of it, and the same seed gives the same world.
//
// The design as revised by the lead (2026-11-13) is the default; each first reading is a variant beside it, measured
// the same way (as round three kept `rule=steps`): `order=all` (a statement counts only after every earlier one of its
// workspace in its log has its body) and `order=off` (each by itself) beside `order=prev`, and `order=whole` (the model's: `prev` names the latest statement whose chain is whole at
// its signer), `off=final` (a keeper that sees the workspace off lets it go for good), `web=at` (a web device counts by its
// `at` alone), reading A of the handover.
//
// LOCK_ROSTER4_RUNS=<n> drawn worlds a row (6 by default), LOCK_ROSTER4_CASES=<n> worlds a scripted row (6),
// LOCK_ROSTER4_STEPS=<n> steps a drawn world (120). Worker threads as lock-roster.test.ts (lock-fork-pool.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { WORKERS, pct, pool, print, toldLines } from "./lock-fork-pool.ts";
import { A3_NAMES, type A4Y, type Family, type Job3, V3, v3Name } from "./lock-roster-model.ts";
import type { Job4, M1Out, M3Out, M5Clock } from "./lock-roster4-model.ts";

const RUNS = Number(process.env.LOCK_ROSTER4_RUNS ?? 6);
const CASES = Number(process.env.LOCK_ROSTER4_CASES ?? 6);
const STEPS = Number(process.env.LOCK_ROSTER4_STEPS ?? 120);

const ask = pool<Job4>(new URL("./lock-roster4-model.ts", import.meta.url), { lockRoster4: true });
const began = performance.now();
const since = () => `${((performance.now() - began) / 1000).toFixed(1)} s since the start`;
const said = (r: Record<string, number>) => Object.entries(r).map(([k, n]) => `${k}: ${n}`).join("; ") || "none";
const FAMILIES: Family[] = ["free", "faults"];
const VON = V3[1];

// ── everything asked at once ────────────────────────────────────────────────────────────────────────────────────────

type Any = Record<string, any>;
const ORDERS = ["prev", "whole", "all", "off"] as const;
const m1Rows = FAMILIES.map((family) => ORDERS.map((order) => ask<M1Out>({ t: "m1", family, runs: RUNS, steps: STEPS, order })));
const lostRows = ORDERS.map((order) => ask<Any>({ t: "lost", order }));
const m2Row = ask<Any>({ t: "m2", n: CASES });
const m3Rows = FAMILIES.map((family) => ask<M3Out>({ t: "m3", family, runs: RUNS, steps: STEPS }));
/// M4: round three's jobs, in its world and in this one.
const R3_JOBS: [string, Job3][] = [
  ...FAMILIES.flatMap((family) => V3.map((v): [string, Job3] => [`drawn ${family} ${v3Name(v)}`, { t: "drawn", family, v, runs: RUNS, steps: STEPS }])),
  ["fold", { t: "fold", seeds: 4, steps: STEPS }],
  ...(["admit", "cancel", "device"] as const).flatMap((y) => (["same", "any"] as const).map((parent): [string, Job3] => [`a2 ${y} ${parent}`, { t: "a2", v: VON, y, parent, n: CASES }])),
  ...A3_NAMES.map((which): [string, Job3] => [`a3 ${which.split(":")[0]}`, { t: "a3", v: VON, which, n: CASES }]),
  ...([["member", "none"], ["member", "admit"], ["member", "cancel new"], ["admin", "none"], ["admin", "cancel new"], ["admin", "cancel adopt"]] as [ "member" | "admin", A4Y][]).map(([role, y]): [string, Job3] => [`a4 ${role} ${y}`, { t: "a4", v: VON, role, y, adopt: y === "cancel adopt", n: CASES }]),
  ...([true, false] as const).map((reach): [string, Job3] => [`b2 ${reach ? "reached" : "unreached"}`, { t: "b2", v: VON, reach, n: CASES }]),
];
const r3Rows = R3_JOBS.map(([, job]) => [ask<Any>({ t: "r3", job, round: 3 }), ask<Any>({ t: "r3", job, round: 4 })] as const);
const m5Clocks = [false, true].flatMap((webAt) => [0, 300, 3600].map((skew) => ask<M5Clock>({ t: "m5clock", skew, webAt })));
const revokedRows = ([["web", false], ["off", false], ["off", true]] as const).flatMap(([kind, offFinal]) => (["same", "any"] as const).map((parent) => ({ kind, parent, offFinal, out: ask<Any>({ t: "revoked", kind, parent, n: CASES, offFinal }) })));
const m6Rows = [false, true].map((offFinal) => ask<Any>({ t: "m6", n: CASES, offFinal }));
const M7_ROWS: { label: string; o: Omit<Extract<Job4, { t: "m7" }>, "t" | "n"> }[] = [
  { label: "the handover", o: {} },
  { label: "s2 away through it", o: { away: true } },
  { label: "a second moved, same place", o: { attack: "same" } },
  { label: "a second moved, any place", o: { attack: "any" } },
  { label: "a second moved, any place, reading A", o: { attack: "any", reading: "A" } },
];
const m7Rows = M7_ROWS.map((r) => ask<Any>({ t: "m7", n: CASES, ...r.o }));
const again = ask<boolean>({ t: "again", steps: STEPS });

// ── the tables ──────────────────────────────────────────────────────────────────────────────────────────────────────

test("M1: agreement with bodies delayed, reordered, and one held back for good", async () => {
  for (const [i, family] of FAMILIES.entries()) {
    for (const [k, order] of ORDERS.entries()) {
      const r = await m1Rows[i][k];
      const d = [...r.delaySteps].sort((a, b) => a - b);
      print(`\n== M1, ${family}, order=${order}: ${RUNS} drawn worlds, ${STEPS} steps, the nth body after the setup never given to one station ==`);
      print(`came to rest ${pct(r.rested, r.runs)}; every keeper the workspace has but the held-back one in one state (D4) ${pct(r.agree, r.runs)}; a fresh keeper given the same entries and bodies shuffled differs ${r.same}/${r.sameChecks}`);
      print(`held-back body's statement on that station's active chain in ${r.heldOnChain} worlds: its state differs ${r.differ}, lets in other keys ${r.letInDiff}, lists the entry as lacking ${r.listed}, statements after it held up there ${r.heldUp}, level the moment the body is given ${r.level}`);
      print(`with nothing held back: (keeper, statement) pairs ready ${r.readyPairs}, in force only later ${r.delayed} (steps late: median ${d[Math.floor(d.length / 2)] ?? 0}, p90 ${d[Math.floor(0.9 * d.length)] ?? 0}, max ${d.at(-1) ?? 0}); ready and not in force at the end ${r.neverIn}`);
      print(`gating at the end: bodies a keeper the workspace has lacks while another keeper keeps them ${r.stuckHeld}, that no keeper keeps ${r.stuckNone}`);
      if (r.stuckLog) toldLines(`M1 ${family} order=${order}, a body not given`, r.stuckLog);
      print(`bodies not taken from messages: ${said(r.refused)}; keepers that let go: ${r.letGo}`);
      if (r.smallest) for (const l of r.smallest) print(`  ${l}`);
      assert.equal(r.oracleBad, 0, "with nothing lacking, the kept bodies and every body made give different states");
      print(`(the model's check: ${r.oracle} keepers lacking nothing, the state from every body made the same at all)`);
    }
  }
});

test("M1: a body lost with its device", async () => {
  for (const [i, order] of ORDERS.entries()) {
    const r = await lostRows[i];
    print(`order=${order}: alice's app lost with the body of an admit it gave the stations the entry of; its own next statement (signed knowing it) in force at ${r.through}/3 stations; her phone's two statements after it in force at ${r.inForce}/${r.later} (station, statement) pairs; xena in the list at ${r.xena}/3 stations; lacking listed ${r.lacking}`);
    if (i === 0) toldLines("lost body", r.log.slice(-14));
  }
});

test("M2: a body is only its commitment's", async () => {
  const r = await m2Row;
  print(`\n== M2: every keeper of both workspaces offered four bodies that are not their commitment's, ${CASES} worlds ==`);
  print(`offered: ${said(r.offered)}; taken: ${r.taken}; why not: ${said(r.why)}; control (a kept body offered again): ${r.controlTaken}/${r.control} taken`);
});

test("M3: two workspaces, one person in both", async () => {
  for (const [i, family] of FAMILIES.entries()) {
    const r = await m3Rows[i];
    print(`\n== M3, ${family}: ${RUNS} drawn worlds; alice signs for both in her one log; W2's stations w0, w1 keep her log and mallory's ==`);
    print(`(a) bodies of W1 kept at W2's stations: ${r.w1Bodies}; what they store naming W1: ${said(r.hits)}`);
    print(`    what they can tell: ${r.otherCommits} commitments of another tag in alice's log (at most ${r.otherTags} tag(s) a station), spread over ${r.spanSecs.length ? `${Math.min(...r.spanSecs)}-${Math.max(...r.spanSecs)}` : "-"} s`);
    print(`(b) W1's state as without W2's statements: ${pct(r.sameW1, r.runs)}; W2's as without W1's: ${pct(r.sameW2, r.runs)}; one state at W1's stations ${pct(r.agreeW1, r.runs)}, at W2's ${pct(r.agreeW2, r.runs)}`);
    if (r.firstDiff) for (const l of r.firstDiff) print(`  ${l}`);
  }
});

test("M4: round three's measures, with bodies in the way", async () => {
  print(`\n== M4: round three's jobs in its world (r3) and this one's (r4) ==`);
  const pick = (label: string, o: Any): string => {
    if (label.startsWith("drawn")) return `agree ${o.agree} same✗ ${o.same}/${o.sameChecks} stmt✗ ${o.attackInForce} acc ${o.accomplice} mal ${o.mallory} rem ${o.removedIn} turned ${o.unasked} inForce ${o.o.inForce}/${o.intents} lost ${o.o.lost} void ${Object.values(o.o.void as Record<string, number>).reduce((a, b) => a + b, 0)} forged ${o.forged}`;
    if (label === "fold") return `compared ${o.compared} differ ${o.differ.length} new kinds refused ${o.wsRefused}/${o.wsChains}`;
    if (label.startsWith("a2")) return `inForce ${o.inForce} changed ${o.changed} phone ${o.phone} before ${o.before} ever ${o.ever}`;
    if (label.startsWith("a3")) return `agree ${o.agree} flap ${o.flap} back ${o.back} xenaIn ${o.inEnd}`;
    if (label.startsWith("a4")) return `old∧both ${o.oldWhileBoth} oldEnd ${o.oldEnd} newEnd ${o.newEnd} mallory ${o.malloryEnd} xena ${o.xenaEnd} cut ${o.cutOld}/${o.cutNew}`;
    return `after: ${(o.after as [string, number][]).map(([k, n]) => `${n}× ${k}`).join(" | ")}`;
  };
  for (const [i, [label]] of R3_JOBS.entries()) {
    const [a, b] = await Promise.all(r3Rows[i]);
    const x = pick(label, a), y = pick(label, b);
    print(`${label}: ${x === y ? `the same: ${x}` : `r3 ${x}\n${" ".repeat(label.length)}  r4 ${y}`}`);
    if (label === "fold") assert.deepEqual(b.differ, [], "the model's rules and personFold differ");
    if (label.startsWith("drawn")) assert.equal(b.forged, false, "a keeper stored a forged entry");
  }
  print(`(M4 printed, ${since()})`);
});

test("M5: web devices", async () => {
  print(`\n== M5: web devices in alice's log ==`);
  for (const c of m5Clocks) {
    const r = await c;
    print(`web=${r.webAt ? "at" : "keeper's clock"}, skew ±${r.skew} s: stations (of 3) letting it in at exp${r.at.map(([off, n]) => ` ${off >= 0 ? "+" : ""}${off}s: ${n}`).join(",")}; 31 days and a second: ${r.tooLong ?? "taken"}; after web.remove: ${r.removed}; put on by her phone, the phone then taken off: ${r.signerGone} let it in, for ${r.lifeDays} days from its at; an at ten years ahead: ${r.farTaken ? `taken by the log's rules, let in now at ${r.farNow} stations, counted ${r.farDays} days of a station's own time in all` : "refused"}`);
  }
  for (const row of revokedRows.filter((x) => x.kind === "web")) {
    const r = await row.out;
    print(`a revoked key of alice's puts a web device on after ${row.parent === "same" ? "the removal's parent" : "a parent of its drawing"}: in force at the end at some station ${pct(r.anyEnd, r.n)}, at all ${pct(r.allEnd, r.n)}; keepers differ ${pct(r.differ, r.n)}; mean stations before the sync ${(r.before / r.n).toFixed(1)}`);
    if (r.smallest && row.parent === "any") toldLines("M5 revoked web", r.smallest);
  }
});

test("M6: on and off", async () => {
  for (const [i, offFinal] of [false, true].entries()) {
    const r = await m6Rows[i];
    print(`\n== M6, off=${offFinal ? "final" : "a state"}: ${CASES} worlds ==`);
    print(`bob (an admin, not the root) signs open and off: keepers whose state changed ${r.notRootChanged}`);
    print(`alice's app signs off: keepers the workspace has saying off ${r.offAt}/${r.keepers}, that let go ${r.letGo}; then her app's ${r.steps} step(s)${offFinal ? " (pin it again, open, the admits and stations again, the root given to each keeper)" : " (an open after its head; then syncs alone)"}: on again ${r.onAgain}/${r.keepers}, the list as before in ${r.sameList}/${r.n} worlds`);
    toldLines(`M6 off=${offFinal ? "final" : "a state"}, seed 1`, r.log.filter((l: string) => !l.startsWith("  it reaches")).slice(-30));
  }
  for (const row of revokedRows.filter((x) => x.kind === "off")) {
    const r = await row.out;
    print(`off=${row.offFinal ? "final" : "a state"}: a revoked key of alice's signs off after ${row.parent === "same" ? "the removal's parent" : "a parent of its drawing"}: off at the end at some station ${pct(r.anyEnd, r.n)}, at all ${pct(r.allEnd, r.n)}; keepers differ ${pct(r.differ, r.n)}; stations let go ${r.letGo}; her steps to have it on ${r.steps.join(",")}; on again with the list as before ${pct(r.recovered, r.n)}`);
    if (r.smallest) toldLines(`M6 revoked off ${row.parent} off=${row.offFinal ? "final" : "a state"}`, r.smallest);
  }
});

test("M7: the handover", async () => {
  print(`\n== M7: a workspace with a chain of its own handed over to alice's log, ${CASES} drawn workspaces a row ==`);
  for (const [i, row] of M7_ROWS.entries()) {
    const r = await m7Rows[i];
    print(`${row.label}: keepers compared (those the workspace has after it) ${r.compared}/${r.keepers}; left behind on purpose in the old chains: ${said(r.behind)}; keepers rooted in alice's log ${r.atAlice}/${r.keepers}, in another ${r.atOther} (in ${r.otherWorlds} worlds), in none ${r.atNone}; one root in ${r.oneRoot}/${r.n} worlds; fields differing from the old chain's state: ${said(r.diffs)}; left out: ${said(r.lost)}; differences no reason covers: ${r.unexplained.length ? r.unexplained.join("; ") : "none"}`);
    assert.equal(r.folds, true, "a keeper's old-chain state is not the product's fold of its chain");
    if (i === 0 && r.example) for (const l of r.example) print(`  ${l}`);
    if (r.otherLog && i >= 3) toldLines(`M7 ${row.label}`, r.otherLog.slice(-30));
  }
  print(`(M7 printed, ${since()}; ${WORKERS} worker threads)`);
});

test("the fourth round's model is deterministic: the same seed, the same world", async () => {
  assert.equal(await again, true);
});
