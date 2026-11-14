// The handover's plan (src/lock-handover.ts `handOverPlan`) held to the fourth round's model's handover that waits for
// nobody (station/test/lock-roster4-model.ts `m8`, its D6): on the model's drawn worlds, the core is given what alice's
// app holds as the model's `moved` lands (the old chain's active chain before it, the person logs, the bodies kept, the
// model's clock), and it hands the chain over (not refused, nothing said, nobody waited for), the state the rules make
// as if moved being the model's state after the `moved` (D4: members, roles, emails, logs, each app by its signer, web
// pages, stations, settings), which M8 holds to the chain's list at its head. LOCK_HANDOVER_MODEL_SEEDS (24) gives more.
import assert from "node:assert/strict";
import { test } from "node:test";
import { type D4, d4Diff, d4Said, look4, m8 } from "../../../station/test/lock-roster4-model.ts";
import { WS } from "../../../station/test/lock-world-sim.ts";
import type { Entry } from "../src/lock.ts";
import { type AsIf, handOverPlan } from "../src/lock-handover.ts";

const SEEDS = Number(process.env.LOCK_HANDOVER_MODEL_SEEDS ?? 24);

/// The core's state as if moved as D4 has one (an unbound member's log "none", as the model says it).
function d4Of(s: AsIf): D4 {
  const members = new Map<string, D4["members"] extends Map<string, infer M> ? M : never>();
  for (const [m, x] of s.members) {
    const devs = [...s.devices].filter(([, d]) => d.sub === m);
    members.set(m, {
      role: x.role, email: x.email, lock: x.lock || "none",
      apps: devs.flatMap(([, d]) => (d.kind === "app" && d.sign_key ? [d.sign_key] : [])).sort(),
      webs: devs.flatMap(([id, d]) => (d.kind === "web" ? [id] : [])).sort(),
    });
  }
  return { on: s.on, settings: s.settings ?? "-", members, stations: [...s.stations].sort() };
}

test("the handover's plan is the model's handover that waits for nobody (m8): not refused, and the state as if moved is the model's after the moved", () => {
  const rows: string[] = [];
  const c = { worlds: 0, planned: 0, refused: 0, members: 0 };
  look4.at = (w, where) => {
    if (!where.endsWith(", moved") || !where.startsWith("m8 ")) return;
    const A = w.dev("alice's app");
    const k = w.x.old.get(A.h)!;
    const active = k.active.map((x) => k.store.get(x)!) as unknown as Entry[];
    const entries = active.slice(0, active.findIndex((e) => e.kind === "moved"));
    const chains = new Map([...A.h.logs].map(([g, l]) => [g, l.active.map((x) => l.store.get(x)!) as unknown as Entry[]]));
    const who = { sub: "alice", genesis: A.log, key: A.signer.id, base: A.base.hex, signer: A.signer.id };
    // (as the core works it out just before signing: the moved after the chain held, by its clock then)
    const p = handOverPlan(WS, entries, who, chains, [...w.keptOf(A.h).values()], w.t - 1);
    c.planned++;
    if ("refused" in p) {
      c.refused++;
      rows.push(`${where}: refused (${p.refused})`);
      return;
    }
    const want = w.d4(A.h);
    const mine = d4Of(p.asIf);
    if (typeof want !== "string") c.members += want.members.size;
    for (const d of d4Diff(want, mine)) rows.push(`${where}: the state as if moved differs in ${d}: the model ${d4Said(want).slice(0, 300)}; the core ${d4Said(mine).slice(0, 300)}`);
  };
  try {
    for (let seed = 1; seed <= SEEDS; seed++) {
      for (const o of [{}, { away: true }]) m8(seed, o);
      c.worlds += 2;
    }
  } finally {
    look4.at = null;
  }
  console.log(`handover vs model: ${c.worlds} worlds of M8, planned ${c.planned}, refused ${c.refused}, members compared ${c.members}; ${rows.length} differ`);
  for (const r of rows.slice(0, 6)) console.log(`  ${r}`);
  assert.ok(c.planned > 0, "some worlds planned");
  assert.equal(rows.length, 0, "the core's handover differs from the model's (the first are printed above)");
});
