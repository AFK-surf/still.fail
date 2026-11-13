// The handover's plan (src/lock-handover.ts `handOverPlan`) held to the fourth round's model's own handover
// (station/test/lock-roster4-model.ts `m7`, its D5): on the model's drawn worlds, the core is given what alice's app
// holds just before the model's handover begins (the old chain's active chain, the person logs, the bodies kept, the
// model's clock) and what it would say is what the model says (each statement's kind, its order, its `prev` as the
// statement before it, every field of its body but the salt; her web pages, as a set), and the state the rules make as
// if moved once it is said is the model's state after the `moved` (D4: members, roles, emails, logs, each app by its
// signer, web pages, stations, settings). LOCK_HANDOVER_MODEL_SEEDS (24) gives more.
//
// Where the two differ on purpose, counted and printed, never compared:
// - a member the chain names with no person log bound: the model leaves them out (its `lost`); every member of `m7`
//   has an app device that signs, so the core waits for them (`waits`, views/lock.ts `lock_not_ready`) and says nothing;
// - another member's web pages: the model writes them into that member's own log from their own app as the handover
//   goes; the core says only its own person's (their pages are out until their own app approves them again);
// - where the web pages go in alice's log: the core signs them before the statements in the same ask (personal-lock.ts
//   `say`'s `also`), the model after; statements' `prev`s name statements alone, so neither changes the other.
import assert from "node:assert/strict";
import { test } from "node:test";
import { hashOf } from "../../../station/test/lock-fork-choice-model.ts";
import { type D4, World4, d4Diff, d4Said, look4, m7 } from "../../../station/test/lock-roster4-model.ts";
import type { Dev3 } from "../../../station/test/lock-roster-model.ts";
import { WS } from "../../../station/test/lock-world-sim.ts";
import { type Entry, canonical } from "../src/lock.ts";
import { type AsIf, type HandOverPlan, handOverPlan } from "../src/lock-handover.ts";
import { bodyHash } from "../src/lock-moved.ts";
import { bodiesOf, byHash } from "../src/lock-statements.ts";

const SEEDS = Number(process.env.LOCK_HANDOVER_MODEL_SEEDS ?? 24);

// deno-lint-ignore no-explicit-any
type J = any;

/// What the core was given and planned as the model's handover began, for one world.
type Snap = { plan: HandOverPlan; mine: Entry[]; kept: J[]; logLength: number; genesis: string; now: number };

/// The bodies as compared: the salt left out, `prev` as the place in the list of the statement it names (`-1`: one
/// before the list, `null`: none).
const comparable = (bodies: J[]): string[] => {
  const at = new Map(bodies.map((b, i) => [bodyHash(b), i]));
  return bodies.map((b) => canonical({ ...b, salt: "", prev: b.prev === null ? null : (at.get(b.prev) ?? -1) }));
};

/// The core's state as if moved as D4 has one (the root's member by the root, as `d4Old` has it).
function d4Of(s: AsIf, root: string, sub: string): D4 {
  const members = new Map<string, D4["members"] extends Map<string, infer M> ? M : never>();
  for (const [m, x] of s.members) {
    const devs = [...s.devices].filter(([, d]) => d.sub === m);
    members.set(m, {
      role: x.role, email: x.email, lock: m === sub ? root : x.lock || "none",
      apps: devs.flatMap(([, d]) => (d.kind === "app" && d.sign_key ? [d.sign_key] : [])).sort(),
      webs: devs.flatMap(([id, d]) => (d.kind === "web" ? [id] : [])).sort(),
    });
  }
  return { on: s.on, settings: s.settings ?? "-", members, stations: [...s.stations].sort() };
}

test("the handover's plan is the model's own handover (m7): its statements, their order and prev, her web pages, and the state after", () => {
  const snaps = new WeakMap<World4, Snap>();
  const proto = World4.prototype as unknown as { sign: (this: World4, d: Dev3, kind: string, body: unknown, o?: unknown) => unknown };
  const sign = proto.sign;
  const own = Object.hasOwn(World4.prototype, "sign");
  // (the model's handover begins with alice's app signing `ws.open` of WS: what her app holds then is the core's)
  proto.sign = function (d, kind, body, o) {
    if (kind === "ws.open" && (body as J)?.ws === WS && d.sub === "alice" && !snaps.has(this)) {
      const k = this.x.old.get(d.h)!;
      const entries = k.active.map((x) => k.store.get(x)!) as unknown as Entry[];
      const chains = new Map([...d.h.logs].map(([g, l]) => [g, l.active.map((x) => l.store.get(x)!) as unknown as Entry[]]));
      const kept = [...this.keptOf(d.h).values()];
      const who = { sub: "alice", genesis: d.log, key: d.signer.id, base: d.base.hex, signer: d.signer.id };
      const plan = handOverPlan(WS, entries, who, chains, kept, this.t);
      lastSnap = { plan, mine: chains.get(d.log)!, kept, logLength: chains.get(d.log)!.length, genesis: d.log, now: this.t };
      snaps.set(this, lastSnap);
    }
    return sign.call(this, d, kind, body, o);
  };
  const rows: string[] = [];
  const c = { unbound: 0, worlds: 0, said: 0, statements: 0, webs: 0, waits: 0, state: 0, othersWebs: 0, refused: 0 };
  let model: { said: J[]; webs: string[] } | null = null;
  let after: D4 | string | null = null;
  look4.at = (w, where) => {
    const A = w.dev("alice's app");
    const l = A.h.logs.get(A.log)!;
    const log = l.active.map((x) => l.store.get(x)!);
    const snap = snaps.get(w);
    if (snap === undefined) return;
    if (where.endsWith("said again in alice's log")) {
      const mine = log.slice(snap.logLength);
      model = {
        said: mine.filter((e) => e.kind === "ws").map((e) => w.x.bodies.get((e.body as J).h)),
        webs: mine.filter((e) => e.kind === "web").map((e) => canonical(e.body)).sort(),
      };
    } else if (where.endsWith(", moved")) after = w.d4(A.h);
  };
  try {
    for (let seed = 1; seed <= SEEDS; seed++) {
      model = null;
      after = null;
      const out = m7(seed, {});
      c.worlds++;
      const w = `m7 seed ${seed}`;
      // (the snapshot is of the world m7 made: found by the hook's last world)
      const snap = lastSnap;
      lastSnap = null;
      if (snap === null || model === null || after === null) {
        rows.push(`${w}: the model's handover was not seen`);
        continue;
      }
      const m = model as { said: J[]; webs: string[] };
      const unbound = out.lost.filter((x) => x.endsWith("bound no person log")).map((x) => x.split(" ")[1]!.replace(/:$/, "")).sort();
      const p = snap.plan;
      if ("refused" in p && p.refused === "the chain does not bind this person to the log pinned here") {
        c.unbound++;
        continue;
      }
      if ("refused" in p) {
        c.refused++;
        rows.push(`${w}: the core refuses (${p.refused}); the model says ${m.said.length}, leaving out ${out.lost.join("; ") || "nobody"}`);
        continue;
      }
      if ("waits" in p) {
        c.waits++;
        if (p.waits.join() !== unbound.join()) rows.push(`${w}: the core waits for ${p.waits.join(",")}; the model leaves out ${unbound.join(",") || "nobody"}`);
        continue;
      }
      if (unbound.length > 0) rows.push(`${w}: the core does not wait for ${unbound.join(",")}, whom the model leaves out`);
      const left = out.lost.filter((x) => !x.endsWith("bound no person log") && !x.startsWith("web "));
      if (left.length > 0) rows.push(`${w}: the model leaves out ${left.join("; ")}, the core says them`);
      c.said++;
      const core = comparable(bodiesOf(WS, p.says, snap.mine, byHash(snap.kept), () => "0".repeat(32)) as J[]);
      const theirs = comparable(m.said);
      c.statements += theirs.length;
      if (core.join("\n") !== theirs.join("\n")) {
        const i = core.findIndex((x, j) => x !== theirs[j]);
        rows.push(`${w}: statement ${i}: the core ${core[i] ?? "none"}; the model ${theirs[i] ?? "none"}`);
      }
      const webs = p.webs.map((x) => canonical({ id: x.id, label: x.label, exp: x.exp })).sort();
      c.webs += m.webs.length;
      if (webs.join() !== m.webs.join()) rows.push(`${w}: her web pages: the core ${webs.join(" ") || "none"}; the model ${m.webs.join(" ") || "none"}`);
      // the state after: the model's after the moved, the core's as if moved once said
      c.state++;
      const mine = d4Of(p.asIf, snap.genesis, "alice");
      const theirsAfter = after as D4 | string;
      for (const d of d4Diff(theirsAfter, mine)) {
        const [kind, sub] = d.split(" ");
        if (kind === "web" && sub !== "alice" && typeof theirsAfter !== "string" && (theirsAfter.members.get(sub!)?.webs.length ?? 0) > 0 && (mine.members.get(sub!)?.webs.length ?? 0) === 0) {
          c.othersWebs++;
          continue;
        }
        rows.push(`${w}: the state after differs in ${d}: the model ${d4Said(theirsAfter).slice(0, 300)}; the core ${d4Said(mine).slice(0, 300)}`);
      }
    }
  } finally {
    if (own) proto.sign = sign;
    else delete (World4.prototype as unknown as { sign?: unknown }).sign;
    look4.at = null;
  }
  console.log(`handover vs model: ${c.worlds} worlds; said and compared ${c.said} (${c.statements} statements, ${c.webs} of her web pages), the state after ${c.state}; waited (the model leaves the unbound out) ${c.waits}; refused as the chain binds not alice to her log (the model hands over by it all the same) ${c.unbound}; refused otherwise ${c.refused}; another member's web pages out on purpose ${c.othersWebs}; ${rows.length} differ`);
  for (const r of rows.slice(0, 6)) console.log(`  ${r}`);
  assert.ok(c.said > 0, "some worlds said");
  assert.equal(rows.length, 0, "the core's handover differs from the model's (the first are printed above)");
});

let lastSnap: Snap | null = null;
