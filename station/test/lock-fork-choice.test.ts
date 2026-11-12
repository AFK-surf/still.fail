// Tailnet Lock's fork-choice rule over the workspace lock's own entries (lock-fork-choice-model.ts): what holds of our
// requirements under it, measured on the same seeds in every variant and printed as tables, each property that does
// not hold with the smallest world that shows it, told step by step. The measurements are the result: nothing here
// asserts that the rule keeps a requirement. What is asserted is only the model's own soundness: no keeper stores what
// a relay forged, and the same seed gives the same world.
//
// The worlds run in worker threads (LOCK_FORK_WORKERS, by default `availableParallelism()` and at most 6:
// lock-fork-pool.ts), every job queued at once, the longest first; the tables are printed in order as the jobs come back.
// Variants that cannot differ in a table are run once, and the table says which stand for which: in the drawn worlds
// without faults `hashfield` (only a revoked key's entries use it, and none signs there), in the scripted cases `offers`
// (and, in 3e, `resign`) by every number of a run of all 32 (2026-11-12). LOCK_FORK_ALL=1 runs all 32 everywhere.
//
// LOCK_FORK_RUNS=<n> drawn worlds a variant and family (6 by default), LOCK_FORK_CASES=<n> worlds a scripted case and
// variant (6), LOCK_FORK_LONG=<n> worlds a variant of the repeated contest and of a key revoked long ago (4),
// LOCK_FORK_STEPS=<n> steps a drawn world (120).
//
// LOCK_FORK_ADDITIONS=1 runs the second round as well (2026-11-12): three additions, NOT part of Tailscale's
// fork-choice rule as modelled in the first (`tie=signer` is ours; `recovery` and `retain` are the lead's reading of
// Tailscale's retroactive revocation and compaction), each on alone and all together, beside the baseline.
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BUCKETS, CASE_NAMES, type CkRow, type Family, type Job, PROPS, type Smallest, type Variant, VARIANTS, revokeCase, twoAfterOne, variantName, withheld, drawn,
  drawSteps,
} from "./lock-fork-choice-model.ts";
import { WORKERS, mean, pct, pool, print, row, toldLines } from "./lock-fork-pool.ts";

const RUNS = Number(process.env.LOCK_FORK_RUNS ?? 6);
const CASES = Number(process.env.LOCK_FORK_CASES ?? 6);
const STEPS = Number(process.env.LOCK_FORK_STEPS ?? 120);
const LONG = Number(process.env.LOCK_FORK_LONG ?? 4);
const ALL = process.env.LOCK_FORK_ALL === "1";
const ADDITIONS = process.env.LOCK_FORK_ADDITIONS === "1";
const W0 = 38;
const began = performance.now();
const since = () => `${((performance.now() - began) / 1000).toFixed(1)} s since the start`;

// ── folding ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The variants a table runs: each stands for those equal to it but for the fields `fold` names (the first of them in
/// VARIANTS' order).
function kept(fold: (keyof Variant)[]): { v: Variant; also: Variant[] }[] {
  const out: { v: Variant; also: Variant[] }[] = [];
  for (const v of VARIANTS) {
    const same = ALL ? undefined : out.find((o) => (Object.keys(v) as (keyof Variant)[]).every((k) => fold.includes(k) || o.v[k] === v[k]));
    if (same) same.also.push(v);
    else out.push({ v, also: [] });
  }
  return out;
}
const foldSaid = (ks: { v: Variant; also: Variant[] }[], why: string) => {
  if (ks.every((k) => k.also.length === 0)) return;
  print(`(${ks.length} of ${VARIANTS.length} variants run, ${why}; each row stands for: ${ks.map((k) => `${variantName(k.v)} = ${[variantName(k.v), ...k.also.map(variantName)].join(" + ")}`).join("; ")})`);
};

// ── the pool (lock-fork-pool.ts) ───────────────────────────────────────────────────────────────────────────────────

const ask = pool<Job>(new URL("./lock-fork-choice-model.ts", import.meta.url), { lockForkChoice: true });

// ── everything asked at once, the longest first ─────────────────────────────────────────────────────────────────────

type CaseRow = { fail: number; before: number; rb: number; smallest: Smallest; exact: number; ck: CkRow };
type LongRow = { fail: number; rb: number; smallest: Smallest; exact: number; ck: CkRow };
type ContestRow = { rounds: number[]; drops: number[]; ends: Record<string, number>; failed: number; exact: number; ck: CkRow; smallest: Smallest };
type OfflineRow = { agree: number; kept: number; stored: number; fail: number; disagree: Smallest; failed: Smallest };
type DrawnRow = {
  agree: number; probe: number; revoc: number; honest: number; inact: number; lost: number; voided: number; turned: number; awayEnd: number; attackAt: number;
  attacks: number; rested: number; forged: boolean; p50: number; p90: number; max: number; hist: number[]; firstBad: Record<string, number>;
};

const LONG_KINDS = [["approve", "same"], ["approve", "any"], ["remove", "same"], ["remove", "any"]] as const;
const longKept = kept(["offers", "resign"]);
const caseKept = kept(["offers"]);
const drawnKept: Record<Family, ReturnType<typeof kept>> = { free: kept(["hashfield"]), faults: kept([]) };

const longs = longKept.map((k) => LONG_KINDS.map(([y, parent]) => ask<LongRow>({ t: "long", v: k.v, y, parent, n: LONG })));
const cases = caseKept.map((k) => CASE_NAMES.map((name) => ask<CaseRow>({ t: "case", name, v: k.v, n: CASES })));
const contests = caseKept.map((k) => (["approve", "remove"] as const).map((y) => ask<ContestRow>({ t: "contest", v: k.v, y, n: LONG })));
const contestLog = ask<{ rounds: number; end: string; perRound: number[]; why: string[]; log: string[] }>({ t: "contestLog", v: VARIANTS.find((v) => v.resign === "on")! });
const drawnRows: Record<Family, Promise<DrawnRow>[]> = {
  free: drawnKept.free.map((k) => ask<DrawnRow>({ t: "drawn", family: "free", v: k.v, runs: RUNS, steps: STEPS })),
  faults: drawnKept.faults.map((k) => ask<DrawnRow>({ t: "drawn", family: "faults", v: k.v, runs: RUNS, steps: STEPS })),
};
// The smallest world of each property and resign mode: its first variant and seed, cut down, as soon as the rows are in.
const shrinks: Record<Family, Promise<Map<string, { v: Variant; seed: number; out: { len: number; revocation: unknown; log: string[] } }>>> = {} as never;
for (const family of ["free", "faults"] as Family[]) {
  shrinks[family] = Promise.all(drawnRows[family]).then(async (rows) => {
    const first = new Map<string, { v: Variant; seed: number }>();
    rows.forEach((r, i) => {
      const v = drawnKept[family][i].v;
      for (const p of PROPS) {
        const k = `${p.name}|${v.resign}`;
        if (r.firstBad[p.name] !== undefined && !first.has(k)) first.set(k, { v, seed: r.firstBad[p.name] });
      }
    });
    const out = new Map<string, { v: Variant; seed: number; out: { len: number; revocation: unknown; log: string[] } }>();
    await Promise.all([...first].map(async ([k, f]) => {
      out.set(k, { ...f, out: await ask({ t: "shrink", family, v: f.v, seed: f.seed, steps: STEPS, prop: k.split("|")[0] }) });
    }));
    return out;
  });
}

// ── the tables ──────────────────────────────────────────────────────────────────────────────────────────────────────

test("drawn worlds, every variant: agreement, revocations, entries made inactive, rollback depth (tables 1, 3e, 4)", async () => {
  for (const family of ["free", "faults"] as Family[]) {
    print(`\n== drawn worlds, ${family === "free" ? "fault-free (delays and reorders only)" : "with every fault (drops, replays, forgeries, revoked keys signing)"}: ${RUNS} seeds a variant, ${STEPS} steps ==`);
    foldSaid(drawnKept[family], "hashfield only shapes what a revoked key signs, and none signs without faults");
    const widths = [W0, 7, 7, 8, 9, 7, 7, 8, 9, 9, 8, 18];
    print(row(["variant", "agree", "probe✗", "revoc✗", "inact/hon", "lost/w", "void/w", "turned", "away@end", "attacks/w", "attack@", "rollback p50/p90/max"], widths));
    const rows = await Promise.all(drawnRows[family]);
    const hist = BUCKETS.map(() => 0);
    let changes = 0, deepest = 0;
    rows.forEach((r, i) => {
      assert.equal(r.forged, false, `a keeper stored a forged entry (${variantName(drawnKept[family][i].v)})`);
      print(row([variantName(drawnKept[family][i].v), pct(r.agree, RUNS), pct(r.probe, RUNS), pct(r.revoc, RUNS), pct(r.inact, r.honest), (r.lost / RUNS).toFixed(2), (r.voided / RUNS).toFixed(2), pct(r.turned, RUNS), pct(r.awayEnd, RUNS), (r.attacks / RUNS).toFixed(2), (r.attackAt / RUNS).toFixed(1), `${r.p50}/${r.p90}/${r.max}`], widths));
      if (r.rested < RUNS) print(`  (${RUNS - r.rested} worlds did not come to rest within 200 rounds of syncs)`);
      // (a folded variant's changes count as often as it stands for, as when all were run)
      const times = 1 + drawnKept[family][i].also.length;
      r.hist.forEach((n, b) => (hist[b] += n * times));
      changes += r.hist.reduce((a, b) => a + b, 0) * times;
      deepest = Math.max(deepest, r.max);
    });
    print("columns: agree = worlds whose keepers all go by one chain in the end; probe✗ = worlds where a trusted device's no-op after its head is not active at every keeper; revoc✗ = worlds where a device taken out is trusted again, its accomplice is, its revoked key's entry is active, or what it signed after it was taken out is active, at a keeper; inact/hon = honest entries ever made inactive at a keeper, of those signed; lost/w, void/w = honest intents on no final chain a world (void: the rules refused to sign it again); turned = worlds where a station turned a person's device away that no honest entry took out; away@end = still so at the end; attacks/w = entries a revoked key signed, a world; attack@ = the most keepers at which one was active, a world; rollback = entries one change of a keeper's active chain made inactive");
    print(`rollback depth, all variants pooled (${changes} changes): ${BUCKETS.map((b, i) => `${i === 0 ? 1 : BUCKETS[i - 1] + 1}${b === Infinity ? "+" : b === (i === 0 ? 1 : BUCKETS[i - 1] + 1) ? "" : `-${b}`}: ${hist[i]}`).join(", ")}; max ${deepest}`);
    const small = await shrinks[family];
    for (const p of PROPS) {
      for (const resign of ["off", "on"]) {
        const f = small.get(`${p.name}|${resign}`);
        if (!f) {
          print(`${p.name}: in no world with resign=${resign}`);
          continue;
        }
        print(`${p.name}: first in ${variantName(f.v)}, seed ${f.seed}; ${f.out.len} of ${STEPS} steps still show it${p.name.startsWith("a revocation") ? ` (${JSON.stringify(f.out.revocation)})` : ""}`);
        toldLines(p.name, f.out.log);
      }
    }
  }
  print(`(drawn worlds printed, ${since()})`);
});

test("the three worlds that fail on this branch, under the rule (table 2)", () => {
  print("\n== the three worlds that fail today, under the rule ==");
  const groups = (f: (v: Variant) => string) => {
    const by = new Map<string, string[]>();
    for (const v of VARIANTS) {
      const k = f(v);
      by.set(k, [...(by.get(k) ?? []), variantName(v)]);
    }
    for (const [k, vs] of by) print(`  [${vs.length} variants: ${vs.join(" | ")}]\n    ${k}`);
  };
  print("1. one device (alice's app) signing twice after the genesis, each entry reaching another station first:");
  groups((v) => twoAfterOne(v, false).said);
  print("2. two devices at once (alice's app, bob's app) after the genesis, each reaching another station first:");
  groups((v) => twoAfterOne(v, true).said);
  print("3. alice's phone taken out; s2 cut off misses it; the phone's key approves its accomplice after the chain from before, at s2; s2 back:");
  groups((v) => {
    const o = revokeCase(0, v, { revoker: "alice's app", target: "alice's phone", y: "approve", parent: "same", before: 0, between: 0, cut: 2 });
    return `active before s2 heard: at ${o.activeBefore} keeper(s); after: ${o.fail ? `fails: ${o.why.join(", ")}` : "inactive at every keeper, the phone trusted nowhere"}`;
  });
  toldLines(`world 2 in ${variantName(VARIANTS[0])}`, twoAfterOne(VARIANTS[0], true).w.log);
  toldLines(`world 3 in ${variantName(VARIANTS[0])}`, revokeCase(0, VARIANTS[0], { revoker: "alice's app", target: "alice's phone", y: "approve", parent: "same", before: 0, between: 0, cut: 2 }).w.log);
});

test("revocation holds against a revoked key's competing entry (tables 3a-3c)", async () => {
  print(`\n== a revoked key's competing entry: ${CASES} seeds a case and variant ==`);
  foldSaid(caseKept, "offers made no difference to any number of these cases in a run of all 32");
  print("a: the phone's key approves its accomplice (alice's app revoked alice's phone: equal votes); b: it removes alice's app instead; c: alice's app (owner) revoked bob's phone (admin), which removes alice's app; c2: as b, alice's laptop signing the same revocation after the same parent too. same: after the revocation's parent; any: after a parent it is trusted in, drawn. Cells: worlds where it fails (the target or its accomplice trusted, or its key's entry active, at a keeper) / mean keepers it was active at before the revocation reached them / the most entries a keeper stopped going by when they met");
  const widths = [W0, ...CASE_NAMES.map(() => 17)];
  print(row(["variant", ...CASE_NAMES], widths));
  const smallest = new Map<string, { s: NonNullable<Smallest>; v: Variant }>();
  for (const [i, k] of caseKept.entries()) {
    const rows = await Promise.all(cases[i]);
    print(row([variantName(k.v), ...rows.map((r) => `${pct(r.fail, CASES)}/${(r.before / CASES).toFixed(1)}/${r.rb}`)], widths));
    rows.forEach((r, c) => {
      const was = smallest.get(CASE_NAMES[c]);
      if (r.smallest && (!was || r.smallest.entries < was.s.entries)) smallest.set(CASE_NAMES[c], { s: r.smallest, v: k.v });
    });
  }
  for (const name of CASE_NAMES) {
    const s = smallest.get(name);
    if (!s) print(`case ${name}: fails in no world`);
    else toldLines(`case ${name} in ${variantName(s.v)} (${s.s.why.join(", ")})`, s.s.log);
  }
  print(`(cases 3a-3c printed, ${since()})`);
});

test("the repeated contest (table 3d)", async () => {
  print(`\n== 3d: the revoked key signs again after an earlier parent each time it is not trusted in the end: ${LONG} seeds ==`);
  foldSaid(caseKept, "offers made no difference to any number of the contest in a run of all 32");
  const widths = [W0, 46, 46];
  print(row(["variant", "approve: rounds mean/max, ends, drops/round mean/max, fails at the end", "remove: same"], widths));
  for (const [i, k] of caseKept.entries()) {
    const cells = (await Promise.all(contests[i])).map((c) => `${mean(c.rounds).toFixed(1)}/${Math.max(...c.rounds)} ${Object.entries(c.ends).map(([e, n]) => `${e}:${n}`).join(",")} ${mean(c.drops).toFixed(1)}/${Math.max(0, ...c.drops)} ${pct(c.failed, LONG)}`);
    print(row([variantName(k.v), ...cells], widths));
  }
  const c = await contestLog;
  toldLines(`3d, seed 1 in ${variantName(VARIANTS.find((v) => v.resign === "on")!)} (${c.rounds} rounds, ${c.end}, drops ${c.perRound.join(",")}; in the end ${c.why.join(", ") || "nothing of it"})`, c.log);
  print(`(case 3d printed, ${since()})`);
});

test("a key revoked long ago (table 3e)", async () => {
  print(`\n== 3e: a key revoked long ago (50 entries after its removal) signs after the removal's parent (same) or any parent it was trusted in: ${LONG} seeds ==`);
  foldSaid(longKept, "offers and resign made no difference to any number of this case in a run of all 32");
  const widths = [W0, ...LONG_KINDS.map(() => 22)];
  print(row(["variant", ...LONG_KINDS.map(([y, p]) => `${y} ${p}: fail/rollback max`)], widths));
  let small: { s: NonNullable<Smallest>; v: Variant; k: string } | null = null;
  for (const [i, k] of longKept.entries()) {
    const rows = await Promise.all(longs[i]);
    print(row([variantName(k.v), ...rows.map((r) => `${pct(r.fail, LONG)}/${r.rb}`)], widths));
    rows.forEach((r, j) => {
      if (r.smallest && (!small || r.smallest.entries < small.s.entries)) small = { s: r.smallest, v: k.v, k: `${LONG_KINDS[j][0]} ${LONG_KINDS[j][1]}` };
    });
  }
  if (small) {
    const s = small as { s: NonNullable<Smallest>; v: Variant; k: string };
    toldLines(`3e ${s.k} in ${variantName(s.v)} (${s.s.why.join(", ")})`, s.s.log);
  }
  print(`(case 3e printed, ${since()}; ${WORKERS} worker threads)`);
});

test("a station that never hears of a revocation keeps trusting the device (5)", () => {
  const r = withheld(VARIANTS[0]);
  print(`\n== 5: withholding ==\ns2, never reached, trusts alice's phone after its removal: ${r.trusts}; any other keeper does: ${r.others}`);
  assert.equal(r.trusts, true, "the model keeps what a station has not heard");
});

test("the model is deterministic: the same seed, the same world", () => {
  const v = VARIANTS[5];
  const a = drawn(7, v, "faults", drawSteps(7, STEPS)), b = drawn(7, v, "faults", drawSteps(7, STEPS));
  assert.deepEqual(a.w.log, b.w.log);
});

// ── the second round: three additions, NOT part of Tailscale's fork-choice rule as modelled ──────────────────────────

/// Each addition alone, all three together, and the baseline (none), on flat and roles, resign off and on, the revoked
/// key's `at` as it is and varied (removal `device`, offers `active`: the first round's representatives).
const ADDED: { name: string; add: Partial<Variant> }[] = [
  { name: "baseline", add: {} },
  { name: "tie=signer", add: { tie: "signer" } },
  { name: "recovery", add: { recovery: "on" } },
  { name: "retain=16", add: { retain: 16 } },
  { name: "all three", add: { tie: "signer", recovery: "on", retain: 16 } },
  { name: "retain=9", add: { retain: 9 } },
  { name: "retain=32", add: { retain: 32 } },
];
const BASES = VARIANTS.filter((v) => v.removal === "device" && v.offers === "active");
const R2 = ADDED.flatMap((a) => BASES.map((b) => ({ group: a.name, v: { ...b, ...a.add } as Variant })));
const R2_FREE = R2.filter((r) => r.v.hashfield === "as-is");
const OFFLINE = ["device", "approve", "remove"] as const;
const awayOf = (v: Variant) => (v.retain ?? 16) + 4;

const r2 = ADDITIONS ? {
  cases: R2.map((r) => CASE_NAMES.map((name) => ask<CaseRow>({ t: "case", name, v: r.v, n: CASES }))),
  contests: R2.map((r) => (["approve", "remove"] as const).map((y) => ask<ContestRow>({ t: "contest", v: r.v, y, n: LONG }))),
  longs: R2.map((r) => LONG_KINDS.map(([y, parent]) => ask<LongRow>({ t: "long", v: r.v, y, parent, n: LONG }))),
  offline: R2.map((r) => OFFLINE.map((who) => ask<OfflineRow>({ t: "offline", v: r.v, who, away: awayOf(r.v), n: CASES }))),
  drawn: {
    free: R2_FREE.map((r) => ask<DrawnRow>({ t: "drawn", family: "free", v: r.v, runs: RUNS, steps: STEPS })),
    faults: R2.map((r) => ask<DrawnRow>({ t: "drawn", family: "faults", v: r.v, runs: RUNS, steps: STEPS })),
  },
} : null;

const sameRows = (name: string) => print(`(the baseline rows are the first round's variants of the same name: compare them with the tables above)\n-- ${name} --`);
const ckSaid = (c: CkRow) => (c.n === 0 ? "-" : `${(c.drops / c.n).toFixed(1)}/${c.dropsMax} ${pct(c.retryActive, c.n)} ${(c.parentsLeft / c.n).toFixed(1)}`);
const smallestOf = (title: string, list: { s: Smallest; label: string }[]) => {
  let best: { s: NonNullable<Smallest>; label: string } | null = null;
  for (const x of list) if (x.s && (!best || x.s.entries < best.s.entries)) best = { s: x.s, label: x.label };
  if (best) toldLines(`${title}, ${best.label}${best.s.why.length ? ` (${best.s.why.join(", ")})` : ""}`, best.s.log);
  else print(`${title}: in no world`);
};

test("second round: drawn worlds with the additions (agreement above all)", { skip: !ADDITIONS && "LOCK_FORK_ADDITIONS=1 runs it" }, async () => {
  for (const family of ["free", "faults"] as Family[]) {
    const list = family === "free" ? R2_FREE : R2;
    print(`\n== second round, drawn worlds, ${family === "free" ? "fault-free" : "with every fault"}: ${RUNS} seeds a variant, ${STEPS} steps ==`);
    sameRows(family === "free" ? "hashfield folded as in the first round" : "every variant");
    const widths = [W0 + 26, 7, 7, 8, 9, 7, 7, 8, 9, 18];
    print(row(["variant", "agree", "probe✗", "revoc✗", "inact/hon", "lost/w", "void/w", "turned", "away@end", "rollback p50/p90/max"], widths));
    const rows = await Promise.all(r2!.drawn[family]);
    rows.forEach((r, i) => {
      assert.equal(r.forged, false, "a keeper stored a forged entry");
      print(row([variantName(list[i].v), pct(r.agree, RUNS), pct(r.probe, RUNS), pct(r.revoc, RUNS), pct(r.inact, r.honest), (r.lost / RUNS).toFixed(2), (r.voided / RUNS).toFixed(2), pct(r.turned, RUNS), pct(r.awayEnd, RUNS), `${r.p50}/${r.p90}/${r.max}`], widths));
      if (r.rested < RUNS) print(`  (${RUNS - r.rested} worlds did not come to rest within 200 rounds of syncs)`);
    });
    // The smallest world of a disagreement and of a revocation that does not hold, for each addition.
    for (const a of ADDED) {
      for (const p of PROPS.filter((x) => x.name === "keepers disagree in the end" || x.name === "a revocation does not hold")) {
        const at = rows.findIndex((r, i) => list[i].group === a.name && r.firstBad[p.name] !== undefined);
        if (at < 0) {
          print(`${a.name}: ${p.name}: in no world`);
          continue;
        }
        const out = await ask<{ len: number; revocation: unknown; log: string[] }>({ t: "shrink", family, v: list[at].v, seed: rows[at].firstBad[p.name], steps: STEPS, prop: p.name });
        print(`${a.name}: ${p.name}: first in ${variantName(list[at].v)}, seed ${rows[at].firstBad[p.name]}; ${out.len} of ${STEPS} steps still show it${p.name.startsWith("a revocation") ? ` (${JSON.stringify(out.revocation)})` : ""}`);
        toldLines(`${a.name}, ${p.name}`, out.log);
      }
    }
  }
  print(`(second round, drawn worlds printed, ${since()})`);
});

test("second round: a revoked key's competing entry, the repeated contest, a key revoked long ago, with the additions", { skip: !ADDITIONS && "LOCK_FORK_ADDITIONS=1 runs it" }, async () => {
  print(`\n== second round, 3a-3c: ${CASES} seeds a case and variant ==`);
  sameRows("cells: fail / trusted set exactly the one meant at every keeper");
  const widths = [W0 + 26, ...CASE_NAMES.map(() => 14)];
  print(row(["variant", ...CASE_NAMES], widths));
  const caseRows = await Promise.all(r2!.cases.map((c) => Promise.all(c)));
  caseRows.forEach((rows, i) => print(row([variantName(R2[i].v), ...rows.map((r) => `${pct(r.fail, CASES)}/${pct(r.exact, CASES)}`)], widths)));
  print("with a recovery key, what its checkpoint did: honest entries of other devices it made inactive, mean/max / the revoked key's try after it active anywhere / parents it can still sign after, mean");
  caseRows.forEach((rows, i) => {
    if (R2[i].v.recovery === "on") print(row([variantName(R2[i].v), ...rows.map((r) => ckSaid(r.ck))], [W0 + 26, ...CASE_NAMES.map(() => 18)]));
  });
  for (const a of ADDED) smallestOf(`3a-3c ${a.name}`, caseRows.flatMap((rows, i) => (R2[i].group === a.name ? rows.map((r, c) => ({ s: r.smallest, label: `case ${CASE_NAMES[c]} in ${variantName(R2[i].v)}` })) : [])));

  print(`\n== second round, 3d: ${LONG} seeds ==`);
  sameRows("cells: rounds mean/max, ends, fails at the end, trusted set exactly the one meant; with a recovery key also its checkpoint as above");
  const contestRows = await Promise.all(r2!.contests.map((c) => Promise.all(c)));
  contestRows.forEach((cs, i) => print(row([variantName(R2[i].v), ...cs.map((c) => `${mean(c.rounds).toFixed(1)}/${Math.max(...c.rounds)} ${Object.entries(c.ends).map(([e, n]) => `${e}:${n}`).join(",")} ${pct(c.failed, LONG)} ${pct(c.exact, LONG)}${c.ck.n > 0 ? ` ck ${ckSaid(c.ck)}` : ""}`)], [W0 + 26, 62, 62])));
  for (const a of ADDED) smallestOf(`3d ${a.name}`, contestRows.flatMap((cs, i) => (R2[i].group === a.name ? cs.map((c, y) => ({ s: c.smallest, label: `${y === 0 ? "approve" : "remove"} in ${variantName(R2[i].v)}` })) : [])));

  print(`\n== second round, 3e: ${LONG} seeds ==`);
  sameRows("cells: fail / trusted set exactly the one meant / rollback max; with a recovery key also its checkpoint as above");
  const longRows = await Promise.all(r2!.longs.map((c) => Promise.all(c)));
  print(row(["variant", ...LONG_KINDS.map(([y, p]) => `${y} ${p}`)], [W0 + 26, ...LONG_KINDS.map(() => 30)]));
  longRows.forEach((rows, i) => print(row([variantName(R2[i].v), ...rows.map((r) => `${pct(r.fail, LONG)}/${pct(r.exact, LONG)}/${r.rb}${r.ck.n > 0 ? ` ck ${ckSaid(r.ck)}` : ""}`)], [W0 + 26, ...LONG_KINDS.map(() => 30)])));
  for (const a of ADDED) smallestOf(`3e ${a.name}`, longRows.flatMap((rows, i) => (R2[i].group === a.name ? rows.map((r, c) => ({ s: r.smallest, label: `${LONG_KINDS[c].join(" ")} in ${variantName(R2[i].v)}` })) : [])));
  print(`(second round, cases printed, ${since()})`);
});

test("second round: a keeper away for longer than it retains", { skip: !ADDITIONS && "LOCK_FORK_ADDITIONS=1 runs it" }, async () => {
  print(`\n== second round, away for retain+4 entries (20 without retain): ${CASES} seeds ==`);
  print("device: bob's app, away, signs after its stale head: one chain in the end / its intent active at every keeper / its entry stored by another keeper. approve, remove: s2 away while alice's phone was taken out and more was signed; the phone's key signs after the chain from before its removal and brings it to s2 alone: one chain in the end / it fails (the phone, its accomplice or its entry kept at a keeper)");
  const rows = await Promise.all(r2!.offline.map((c) => Promise.all(c)));
  const widths = [W0 + 26, 24, 18, 18];
  print(row(["variant", ...OFFLINE], widths));
  rows.forEach((rs, i) => print(row([variantName(R2[i].v), `${pct(rs[0].agree, CASES)}/${pct(rs[0].kept, CASES)}/${pct(rs[0].stored, CASES)}`, `${pct(rs[1].agree, CASES)}/${pct(rs[1].fail, CASES)}`, `${pct(rs[2].agree, CASES)}/${pct(rs[2].fail, CASES)}`], widths)));
  for (const a of ADDED) {
    smallestOf(`away, keepers disagree, ${a.name}`, rows.flatMap((rs, i) => (R2[i].group === a.name ? rs.map((r, c) => ({ s: r.disagree, label: `${OFFLINE[c]} in ${variantName(R2[i].v)}` })) : [])));
    smallestOf(`away, revocation fails, ${a.name}`, rows.flatMap((rs, i) => (R2[i].group === a.name ? rs.map((r, c) => ({ s: r.failed, label: `${OFFLINE[c]} in ${variantName(R2[i].v)}` })) : [])));
  }
  print(`(second round, away printed, ${since()}; ${WORKERS} worker threads)`);
});
