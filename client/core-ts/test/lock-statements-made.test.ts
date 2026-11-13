// What this device makes of what it keeps as it says something of a moved workspace (src/lock-statements.ts) held to
// the fourth round's model (station/test/lock-roster4-model.ts, its defaults): on the model's drawn worlds (both of
// round three's variants, fault-free and with faults; as drawn, one body held back for good, two workspaces), at each
// statement an honest device signs (`World4.make` through `honestOp`; not one it signs again, which is `again`'s), the
// core's body given what that device keeps then (its bodies and its own, the log it signs after) is the model's but for
// the salt; and on round three's scripted re-bindings (`a4`, `a3`'s v), whom the core would say again before a removal
// is whom the model's `adopt` says again. LOCK_STATEMENTS_SEEDS (12) and _STEPS (600) give more.
import assert from "node:assert/strict";
import { test } from "node:test";
import { hashOf } from "../../../station/test/lock-fork-choice-model.ts";
import { World4 } from "../../../station/test/lock-roster4-model.ts";
import { type Dev3, type Family, type Make3, V3, type V3v, a3, a4, drawSteps3 } from "../../../station/test/lock-roster-model.ts";
import type { Key } from "../../../station/test/lock-world-sim.ts";
import { type Entry, canonical, entryHash } from "../src/lock.ts";
import { wsTag } from "../src/lock-moved.ts";
import { type Said, bodyOf, plan } from "../src/lock-statements.ts";

const SEEDS = Number(process.env.LOCK_STATEMENTS_SEEDS ?? 12);
const STEPS = Number(process.env.LOCK_STATEMENTS_STEPS ?? 600);

// deno-lint-ignore no-explicit-any
type J = any;

/// What the model's intent says, as the core's call would say it.
function saidOf(kind: string, b: J): Said {
  switch (kind) {
    case "ws.member": return { kind: "member", sub: b.sub, email: b.email ?? `${b.sub}@x`, lock: b.lock, role: b.role };
    case "ws.member.remove": return { kind: "member.remove", sub: b.sub };
    case "ws.station": return { kind: "station", key: b.key };
    case "ws.station.remove": return { kind: "station.remove", key: b.key };
    case "ws.open": return { kind: "open", origins: b.origins, rp_id: b.rp_id, cloud_keys: b.cloud_keys, email: b.email };
    default: return { kind: "off" };
  }
}

type Counts = { compared: number; differ: string[]; skips: number; multi: number; removals: number; plans: { by: string; says: string[] }[] };

/// A world of the model that, at each honest statement, asks the core what it would make of the same.
class Watched extends World4 {
  signing: Dev3 | undefined;
  counts: Counts | undefined;
  watchPlans = false;

  /// What `d` holds now: its bodies kept and those it signed, by hash; its logs' active chains.
  held(d: Dev3): { kept: Map<string, J>; chains: Map<string, Entry[]> } {
    const kept = new Map<string, J>(this.keptOf(d.h));
    for (const h of this.x.mine.get(d.signer.id) ?? []) if (!kept.has(h)) kept.set(h, this.x.bodies.get(h));
    const chains = new Map([...d.h.logs].map(([g, k]) => [g, k.active.map((x) => k.store.get(x)!) as unknown as Entry[]]));
    return { kept, chains };
  }

  sign(d: Dev3, kind: string, body: unknown, o: { parent?: string; bring?: boolean; log?: string } = {}) {
    if (this.watchPlans && kind === "ws.member.remove" && this.counts) {
      const { kept, chains } = this.held(d);
      const p = plan((body as J).ws, this.root, chains, [...kept.values()], { genesis: d.log, sub: d.sub, key: d.signer.id }, [saidOf(kind, body)], this.t);
      this.counts.plans.push({ by: d.name, says: "why" in p ? [`refused: ${p.why}`] : p.says.map((s) => canonical(s)) });
    }
    const was = this.signing;
    this.signing = d;
    try {
      return super.sign(d, kind, body, o);
    } finally {
      this.signing = was;
    }
  }

  make(parent: Entry & J, kind: string, body: unknown, by: Key, at?: number) {
    const d = this.signing;
    if (!d || !this.counts || this.resigning || !kind.startsWith("ws.") || d.signer.id !== by.id || this.x.reuse !== undefined || this.x.forcePrev !== undefined) return super.make(parent, kind, body, by, at);
    const ws = (body as J).ws as string;
    const { kept } = this.held(d);
    const log = this.chainTo(hashOf(parent)) as unknown as Entry[];
    const core = bodyOf(ws, saidOf(kind, body), log, kept, "0".repeat(32));
    const e = super.make(parent, kind, body, by, at);
    const model = this.x.bodies.get(e.body.h);
    const c = this.counts;
    c.compared++;
    const latest = [...log].reverse().find((y) => y.kind === "ws" && (y.body as J).t === wsTag(ws, entryHash(log[0]!)));
    if ((latest === undefined ? null : (latest.body as J).h) !== core.prev) c.skips++;
    if (Array.isArray(core.cancels)) c.removals++;
    if (Array.isArray(core.cancels) && core.cancels.length > 1) c.multi++;
    const a = canonical({ ...core, salt: "" }), b = canonical({ ...model, salt: "" });
    if (a !== b && c.differ.length < 5) c.differ.push(`${d.name} ${kind}: the core ${a.slice(0, 400)}; the model ${b.slice(0, 400)}`);
    else if (a !== b) c.differ.push("");
    return e;
  }
}

const fresh = (): Counts => ({ compared: 0, differ: [], skips: 0, multi: 0, removals: 0, plans: [] });
const options = (seed: number) => (seed % 3 === 1 ? { holdBack: { station: seed % 3, nth: 1 + ((seed * 7) % 5) } } : seed % 3 === 2 ? { two: true } : {});

test("at each statement an honest device of the model's drawn worlds signs, the core makes its body of what it keeps: its prev, its cancels", () => {
  const c = fresh();
  let worlds = 0;
  for (const v of V3) for (const family of ["free", "faults"] as Family[]) for (let seed = 1; seed <= SEEDS; seed++) {
    const w = new Watched(seed, v as V3v, family, options(seed));
    w.counts = c;
    w.run(drawSteps3(seed, STEPS));
    w.finish();
    worlds++;
  }
  console.log(`drawn: ${worlds} worlds, ${c.compared} statements compared, ${c.skips} with a prev past the latest of its tag (a body or its chain not kept), ${c.removals} removals, ${c.multi} of them cancelling more than one; ${c.differ.length} differ`);
  for (const d of c.differ.slice(0, 3)) console.log(`  ${d}`);
  assert.equal(c.differ.length, 0, "the core and the model make different bodies (the first are printed above)");
  assert.ok(c.compared > 0 && c.skips > 0 && c.multi > 0, "not trivial worlds");
});

test("before taking someone out, the core says again whom the model's adopt says again: those the one taken out let in", () => {
  const rows: string[] = [];
  let compared = 0;
  const watching = (c: Counts): Make3 => (seed, v, family, o) => {
    const w = new Watched(seed, v, family, o);
    w.counts = c;
    w.watchPlans = true;
    return w;
  };
  const xena = (w: { home: Map<string, string> }) => canonical({ kind: "member", sub: "xena", email: "xena@x", lock: w.home.get("xena"), role: "member" });
  for (let seed = 1; seed <= SEEDS; seed++) {
    for (const role of ["member", "admin"] as const) for (const adopt of [false, true]) {
      const c = fresh();
      let home: Map<string, string> | undefined;
      a4(seed, V3[1]!, role, "none", adopt, (s, v, f, o) => {
        const w = watching(c)(s, v, f, o);
        home = w.home;
        return w;
      });
      const mine = c.plans.filter((p) => p.by === "bob's app");
      // the model's adopt says xena again where carol, an admin, let her in, and only where it was not said already
      const want = role === "admin" && !adopt ? [xena({ home: home! })] : [];
      const got = mine[0]?.says.filter((s) => !s.includes('"member.remove"')) ?? ["no removal planned"];
      compared++;
      if (canonical(got) !== canonical(want)) rows.push(`a4 seed ${seed} ${role} adopt ${adopt}: the core says again ${got.join(" ") || "none"}; the model ${want.join(" ") || "none"}`);
      if (mine[0] !== undefined && !mine[0].says.at(-1)?.includes('"member.remove"')) rows.push(`a4 seed ${seed} ${role} adopt ${adopt}: the removal is not last: ${mine[0].says.join(" ")}`);
    }
    for (const which of ["v: bob admits xena; later alice removes bob", "v+adopt: as v, alice first admits whom bob admitted"] as const) {
      const c = fresh();
      let home: Map<string, string> | undefined;
      a3(seed, V3[1]!, which, (s, v, f, o) => {
        const w = watching(c)(s, v, f, o);
        home = w.home;
        return w;
      });
      const mine = c.plans.filter((p) => p.by === "alice's app");
      const want = which.startsWith("v:") ? [xena({ home: home! })] : [];
      const got = mine[0]?.says.filter((s) => !s.includes('"member.remove"')) ?? ["no removal planned"];
      compared++;
      if (canonical(got) !== canonical(want)) rows.push(`a3 ${which.split(":")[0]} seed ${seed}: the core says again ${got.join(" ") || "none"}; the model ${want.join(" ") || "none"}`);
    }
  }
  console.log(`take-over: ${compared} removals compared with the model's adopt; ${rows.length} differ`);
  for (const r of rows.slice(0, 4)) console.log(`  ${r.slice(0, 400)}`);
  assert.equal(rows.length, 0, "the core says again other than the model's adopt (printed above)");
});
