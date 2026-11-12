// The third round of the fork-choice model (lock-roster-model.ts, 2026-11-12): a workspace said in its people's own
// person logs, each log chosen between branches by Tailscale's rule with `tie=signer`. What holds of the lead's
// properties (A1-A4, B1, B2) is measured and printed as tables, each one that does not hold with the smallest world that
// shows it, told step by step. The measurements are the result: nothing here asserts that the design keeps a property.
// What is asserted is the model's own soundness: its person-log rules say what `personFold` says on every chain with
// only the product's kinds, no keeper stores what a relay forged, and the same seed gives the same world.
//
// LOCK_ROSTER_RUNS=<n> drawn worlds a family and variant (6 by default), LOCK_ROSTER_CASES=<n> worlds a scripted row
// (6), LOCK_ROSTER_STEPS=<n> steps a drawn world (120), LOCK_ROSTER_FOLD=<n> worlds compared with `personFold` (4).
// Worker threads as lock-fork-choice.test.ts (lock-fork-pool.ts).
//
// The list is worked out by the coordinator's correction of 2026-11-12 (`grounded` in the model: a grounded labelling
// of admits, standings and cancellations); the rows marked `rule=steps` are the lead's steps 1-3 as first given, kept
// beside it to compare.
import assert from "node:assert/strict";
import { test } from "node:test";
import { WORKERS, pct, pool, print, row, toldLines } from "./lock-fork-pool.ts";
import { A3_NAMES, type A4Y, type Family, type Job3, type Outcomes, PROPS3, STEPS_RULE, V3, type V3v, drawSteps3, drawn3, v3Name } from "./lock-roster-model.ts";

const RUNS = Number(process.env.LOCK_ROSTER_RUNS ?? 6);
const CASES = Number(process.env.LOCK_ROSTER_CASES ?? 6);
const STEPS = Number(process.env.LOCK_ROSTER_STEPS ?? 120);
const FOLD = Number(process.env.LOCK_ROSTER_FOLD ?? 4);

const ask = pool<Job3>(new URL("./lock-roster-model.ts", import.meta.url), { lockRoster: true });
const began = performance.now();
const since = () => `${((performance.now() - began) / 1000).toFixed(1)} s since the start`;
const W0 = 22;

// ── everything asked at once, the longest first ─────────────────────────────────────────────────────────────────────

type DrawnRow = {
  rested: number; agree: number; same: number; sameChecks: number; sameWorlds: number; attackInForce: number; accomplice: number; mallory: number; removedIn: number;
  attackAt: number; attacks: number; intents: number; inact: number; honest: number; unasked: number; asked: number; turnedWorlds: number; back: number; forged: boolean;
  rbMax: number; rb90: number; o: Outcomes; firstBad: Record<string, number>; lostWorlds: number; noEffectWorlds: number;
};
type Smallest = { entries: number; log: string[] } | null;
type A2Row = { inForce: number; changed: number; phone: number; before: number; changedBefore: number; ever: number; smallest: Smallest };
type A3Row = { ends: [string, number][]; agree: number; flap: number; back: number; inEnd: number; others: string[]; flapLog: string[] | null; log: string[] };
type A4Row = { oldWhileBoth: number; oldEnd: number; newEnd: number; malloryEnd: number; xenaEnd: number; cutOld: number; cutNew: number; ends: [string, number][]; bad: string[] | null };
type B2Row = { views: [string, number][]; approved: [string, number][]; before: [string, number][]; after: [string, number][]; log: string[] };

const fold = ask<{ compared: number; differ: string[]; wsChains: number; wsRefused: number; wsWhy: string[] }>({ t: "fold", seeds: FOLD, steps: STEPS });
const FAMILIES: Family[] = ["free", "faults"];
/// The drawn worlds' variants: the corrected rule, resign off and on, and the first rule with resign on.
const DRAWN_V: V3v[] = [...V3, STEPS_RULE];
const drawnRows = Object.fromEntries(FAMILIES.map((f) => [f, DRAWN_V.map((v) => ask<DrawnRow>({ t: "drawn", family: f, v, runs: RUNS, steps: STEPS }))])) as Record<Family, Promise<DrawnRow>[]>;
const A2_KINDS = [["admit", "same"], ["admit", "any"], ["cancel", "same"], ["cancel", "any"], ["device", "same"], ["device", "any"]] as const;
const a2Rows = V3.map((v) => A2_KINDS.map(([y, parent]) => ask<A2Row>({ t: "a2", v, y, parent, n: CASES })));
const A4_ROWS: { role: "member" | "admin"; y: A4Y; adopt: boolean }[] = [
  ...(["none", "device", "admit", "cancel new"] as const).map((y) => ({ role: "member" as const, y, adopt: false })),
  ...(["none", "device", "admit", "cancel new"] as const).map((y) => ({ role: "admin" as const, y, adopt: false })),
  ...(["none", "cancel new", "cancel adopt"] as const).map((y) => ({ role: "admin" as const, y, adopt: true })),
];
const VON = V3.find((v) => v.resign === "on")!;
const RULES: V3v[] = [VON, STEPS_RULE];
const a4Rows = RULES.map((v) => A4_ROWS.map((r) => ask<A4Row>({ t: "a4", v, ...r, n: CASES })));
const a3Rows = A3_NAMES.map((which) => RULES.map((v) => ask<A3Row>({ t: "a3", v, which, n: CASES })));
const a4Root = ask<string[]>({ t: "a4root", v: VON });
const b2Rows = ([true, false] as const).map((reach) => ask<B2Row>({ t: "b2", v: VON, reach, n: CASES }));
const counts = (xs: [string, number][], of: number) => xs.sort((a, b) => b[1] - a[1]).map(([k, n]) => `${pct(n, of)} ${k}`);
const said = (r: Record<string, number>) => Object.entries(r).map(([k, n]) => `${k}: ${n}`).join("; ") || "none";

// ── the tables ──────────────────────────────────────────────────────────────────────────────────────────────────────

test("the model's person-log rules say what personFold says on the product's kinds", async () => {
  const f = await fold;
  print(`\n== third round: the model's rules and personFold, ${FOLD} worlds with every fault ==`);
  print(`entries of chains with only genesis, device, device.remove (each with three changed copies): ${f.compared} compared, ${f.differ.length} differ`);
  for (const d of f.differ) print(`  ${d}`);
  print(`chains ending in a ws.* entry given to personFold: ${f.wsChains}, refused ${f.wsRefused} (${f.wsWhy.join("; ")})`);
  assert.ok(f.compared > 0, "nothing was compared");
  assert.deepEqual(f.differ, [], "the model's rules and personFold differ");
});

test("A1, B1 and revocations in drawn worlds", async () => {
  for (const family of FAMILIES) {
    print(`\n== third round, drawn worlds, ${family === "free" ? "fault-free (delays and reorders only)" : "with every fault (drops, replays, forgeries, revoked keys signing)"}: ${RUNS} seeds a variant, ${STEPS} steps ==`);
    const widths = [W0 + 11, 7, 13, 8, 7, 8, 8, 9, 9, 13, 10, 12];
    print(row(["variant", "agree", "same✗ w/chk", "stmt✗", "accomp", "mallory", "removed", "attacks/w", "attack@", "turned w/n", "asked/w", "inact/hon"], widths));
    const rows = await Promise.all(drawnRows[family]);
    rows.forEach((r, i) => {
      assert.equal(r.forged, false, "a keeper stored a forged entry");
      print(row([v3Name(DRAWN_V[i]), pct(r.agree, RUNS), `${pct(r.sameWorlds, RUNS)} ${r.same}/${r.sameChecks}`, pct(r.attackInForce, RUNS), pct(r.accomplice, RUNS), pct(r.mallory, RUNS), pct(r.removedIn, RUNS),
        (r.attacks / RUNS).toFixed(2), (r.attackAt / RUNS).toFixed(1), `${pct(r.turnedWorlds, RUNS)} ${r.unasked}`, (r.asked / RUNS).toFixed(2), pct(r.inact, r.honest)], widths));
      if (r.rested < RUNS) print(`  (${RUNS - r.rested} worlds did not come to rest within 200 rounds of syncs)`);
    });
    print("columns: agree = worlds whose keepers all compute one list (members, roles, bound logs, stations, keys let in) and go by one head of every log in the end (A1); same✗ = worlds where a keeper's list differs from that of a fresh keeper given the same entries in another order, checked at a quarter, half, three quarters and the end (mismatches/checks); stmt✗ = worlds where an entry a revoked key signed is in force at a keeper in the end; accomp = its accomplice let in; mallory = mallory in a list; removed = a key an honest device.remove took out let in; attacks/w = entries a revoked key signed, a world; attack@ = the most keepers one was active at, a world; turned = worlds where a station turned away a key of the honest side that no honest entry took out (device.remove of it, or ws.member.remove of its person; mallory's and accomplices' keys aside) / how many times; asked/w = turned away as asked, a world; inact/hon = honest entries ever made inactive at a keeper, of those signed");
    print("B1, each honest intent in the end (a pending entry is one signed while its device reached no keeper, brought at its next sync):");
    rows.forEach((r, i) => {
      const o = r.o;
      const noEffect = Object.values(o.noEffect).reduce((a, b) => a + b, 0), voided = Object.values(o.void).reduce((a, b) => a + b, 0);
      print(`  ${v3Name(DRAWN_V[i])}: ${r.intents} intents: in force at every keeper and taking effect ${o.inForce} (${pct(o.inForce, r.intents)}); in force everywhere, no effect ${noEffect} (${said(o.noEffect)}) in ${pct(r.noEffectWorlds, RUNS)} of worlds, of which its own device could tell right after signing ${said(o.toldAtSigning)}; marked to its signer as not in effect ${voided} (${said(o.void)}); its device taken out of its log ${o.removedDev}; silently lost ${o.lost} (in ${pct(r.lostWorlds, RUNS)} of worlds); rollback p90/max ${r.rb90}/${r.rbMax}`);
    });
    for (const p of PROPS3) {
      for (const [i, v] of V3.entries()) {
        // (the first rule's rows are for comparison: their smallest worlds were printed in the first pass of round 3)
        const seed = rows[i].firstBad[p.name];
        if (seed === undefined) {
          print(`${p.name}: in no world with ${v3Name(v)}`);
          continue;
        }
        const out = await ask<{ len: number; log: string[]; outcomes: Outcomes }>({ t: "shrink", family, v, seed, steps: STEPS, prop: p.name });
        print(`${p.name}: first with ${v3Name(v)}, seed ${seed}; ${out.len} of ${STEPS} steps still show it${p.name.includes("lost") || p.name.includes("effect") ? ` (${JSON.stringify(out.outcomes)})` : ""}`);
        toldLines(`${family}, ${p.name}, ${v3Name(v)}`, out.log);
      }
    }
  }
  print(`(drawn worlds printed, ${since()})`);
});

test("A2: a key taken out of an admin's log signs workspace statements", async () => {
  print(`\n== third round, A2: bob's phone taken out of bob's log (one station cut off); its key signs after the removal's parent (same) or a parent it was trusted in (any), brought to the cut station (and on odd seeds one device), then every keeper syncs: ${CASES} seeds a row ==`);
  print("admit: mallory admitted as an admin; cancel: carol removed, naming alice's admit of her; device: its accomplice put in bob's log (the first round's case a, in one person's log). Cells: in force at a keeper in the end / the list changed by it at a keeper in the end / the phone itself let in at a station in the end / mean keepers it was in force at before the cut station was back / mean keepers whose list it changed then / mean keepers it was ever active at");
  const widths = [W0, ...A2_KINDS.map(() => 32)];
  print(row(["variant", ...A2_KINDS.map(([y, p]) => `${y} ${p}`)], widths));
  let small: { s: NonNullable<Smallest>; label: string } | null = null;
  for (const [i, v] of V3.entries()) {
    const rows = await Promise.all(a2Rows[i]);
    print(row([v3Name(v), ...rows.map((r) => `${pct(r.inForce, CASES)}/${pct(r.changed, CASES)}/${pct(r.phone, CASES)}/${(r.before / CASES).toFixed(1)}/${(r.changedBefore / CASES).toFixed(1)}/${(r.ever / CASES).toFixed(1)}`)], widths));
    rows.forEach((r, j) => {
      if (r.smallest && (!small || r.smallest.entries < small.s.entries)) small = { s: r.smallest, label: `${A2_KINDS[j].join(" ")}, ${v3Name(v)}` };
    });
  }
  print("(the second round's case a, tie=signer, 400 seeds, the run of 2026-11-12: fails same 0.0%, any 20.3% with flat votes and 53.0% with roles; a person log has flat votes)");
  if (small) {
    const s = small as { s: NonNullable<Smallest>; label: string };
    toldLines(`A2, ${s.label}`, s.s.log);
  } else print("A2: in force at no keeper in the end, in no world");
  print(`(A2 printed, ${since()})`);
});

test("A3: concurrent statements by different people, fault-free", async () => {
  print(`\n== third round, A3: statements signed at once, each brought first to a station the seed draws, deliveries and syncs drawn, then every keeper syncs: ${CASES} seeds a case and rule ==`);
  for (const [i, name] of A3_NAMES.entries()) {
    print(`-- ${name} --`);
    for (const [k, v] of RULES.entries()) {
      const r = await a3Rows[i][k];
      print(`  ${v3Name(v)}: one list at every keeper in the end: ${pct(r.agree, CASES)}; xena's app turned away at a station on the way: ${pct(r.flap, CASES)}, let in again after: ${pct(r.back, CASES)}; let in at every station in the end: ${pct(r.inEnd, CASES)}; others turned away: ${r.others.join(", ") || "none"}`);
      for (const line of counts(r.ends, CASES)) print(`    s0 in the end, ${line}`);
      if (k > 0) continue;
      toldLines(`${name}, seed 1`, r.log.filter((l) => !l.startsWith("  it reaches")));
      if (r.flapLog && !r.flapLog.every((l, x) => l === r.log[x])) toldLines(`${name}, the first seed where xena's app was turned away`, r.flapLog);
    }
  }
  print(`(A3 printed, ${since()})`);
});

test("A4: re-binding a person to a new log", async () => {
  print(`\n== third round, A4: carol (member or admin, admitted by alice) begins a new log from her laptop; one station cut off; bob signs ws.member.remove naming the admits of carol he stored and ws.member binding her to the new log; then her phone's key, revoked by that, signs y on the old log after its head, brought to the cut station and one other keeper; the cut station comes back: ${CASES} seeds a row ==`);
  print("y: device = its accomplice put in the old log; admit = mallory admitted as an admin from the old log; cancel new = carol's removal cancelling bob's new admit; cancel adopt = xena's removal cancelling bob's adopt of her. adopt: bob first admits again whom carol admitted (xena). Cells: an old-log device let in at a keeper where both statements were in force (ever) / an old-log device or its accomplice let in at a keeper in the end / the new device let in at every station in the end / mallory in a list in the end / xena in every list in the end / the cut station, before it was back: lets an old device in, lets the new one in");
  const widths = [50, 10, 9, 9, 9, 9, 14];
  print(row(["row", "old∧both", "old@end", "new@end", "mallory", "xena", "cut: old/new"], widths));
  for (const [x, v] of RULES.entries()) {
    const rows = await Promise.all(a4Rows[x]);
    const label = (k: (typeof A4_ROWS)[number]) => `${k.role} y=${k.y}${k.adopt ? " adopt" : ""}${v.rule === "steps" ? " rule=steps" : ""}`;
    rows.forEach((r, i) => {
      const k = A4_ROWS[i];
      print(row([label(k), pct(r.oldWhileBoth, CASES), pct(r.oldEnd, CASES), pct(r.newEnd, CASES), pct(r.malloryEnd, CASES), k.role === "admin" ? pct(r.xenaEnd, CASES) : "-", `${pct(r.cutOld, CASES)}/${pct(r.cutNew, CASES)}`], widths));
    });
    if (x > 0) continue;
    rows.forEach((r, i) => {
      for (const line of counts(r.ends, CASES)) print(`  ${label(A4_ROWS[i])}: s0 in the end, ${line}`);
    });
    rows.forEach((r, i) => {
      const k = A4_ROWS[i];
      if (r.bad) toldLines(`A4 ${label(k)}, its first seed with an old device let in, the new one not let in, mallory in${k.adopt ? " or xena out" : ""} in the end`, r.bad);
    });
  }
  print("-- M the root owner --");
  for (const line of await a4Root) print(`  ${line}`);
  print(`(A4 printed, ${since()})`);
});

test("B2: a second log begun for someone bound already", async () => {
  print(`\n== third round, B2: carol bound by her app's log; her laptop, which reached no keeper holding it, begins a log of its own; then carol's app approves the laptop on the bound log: ${CASES} seeds (${v3Name(VON)}) ==`);
  for (const [i, reach] of ([true, false] as const).entries()) {
    const r = await b2Rows[i];
    print(`-- the laptop ${reach ? "then syncs with every keeper" : "reaches no keeper at all"} --`);
    for (const line of counts(r.before, CASES)) print(`  before the approval: ${line}`);
    for (const line of counts(r.views, CASES)) print(`  what the laptop can tell then: ${line}`);
    for (const line of counts(r.after, CASES)) print(`  after the approval: ${line}`);
    for (const line of counts(r.approved, CASES)) print(`  what the laptop can tell then: ${line}`);
    toldLines(`B2, seed 1, ${reach ? "reached" : "unreached"}`, r.log);
  }
  print(`(B2 printed, ${since()}; ${WORKERS} worker threads)`);
});

test("the third round's model is deterministic: the same seed, the same world", () => {
  const a = drawn3(7, VON, "faults", drawSteps3(7, STEPS)), b = drawn3(7, VON, "faults", drawSteps3(7, STEPS));
  assert.deepEqual(a.w.log, b.w.log);
});
