// The station held to the fourth round's model (lock-moved-model-check.ts says what is compared and how; where the
// station is stricter on purpose: a state the model calls "not on" or "no root" is one it waits in, naming nobody and
// giving nobody a body). Drawn worlds (both of round three's variants, fault-free and with faults; as drawn, one body
// held back for good, two workspaces) and the scripted ones (M2, M5 with its clocks, a revoked key's web device and
// `off`, M6, M7's four rows). LOCK_MOVED_MODEL_SEEDS, _STEPS, _SCRIPTED give more.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pool, print } from "./lock-fork-pool.ts";
import { V3 } from "./lock-roster-model.ts";
import type { Job, Out } from "./lock-moved-model-check.ts";

const SEEDS = Number(process.env.LOCK_MOVED_MODEL_SEEDS ?? 24);
const STEPS = Number(process.env.LOCK_MOVED_MODEL_STEPS ?? 120);
const SCRIPTED = Number(process.env.LOCK_MOVED_MODEL_SCRIPTED ?? 3);
const BATCH = 4;
const FAMILIES = ["free", "faults"] as const;

const ask = pool<Job>(new URL("./lock-moved-model-check.ts", import.meta.url), { movedModel: true });
const drawnJobs: Job[] = V3.flatMap((_, v) => FAMILIES.flatMap((family) => Array.from({ length: Math.ceil(SEEDS / BATCH) }, (_, i) =>
  ({ t: "drawn", v, family, from: 1 + i * BATCH, to: Math.min(SEEDS, (i + 1) * BATCH), steps: STEPS }) as Job)));
const drawn = Promise.all(drawnJobs.map((j) => ask<Out>(j)));
const scripted = Promise.all(Array.from({ length: SCRIPTED }, (_, i) => ask<Out>({ t: "scripted", from: i + 1, to: i + 1 })));

const sum = (os: Out[]): Out => os.reduce((a, o) => {
  const refused = { ...a.refused };
  for (const [k, n] of Object.entries(o.refused)) refused[k] = (refused[k] ?? 0) + n;
  const out = { ...a, refused, differ: [...a.differ, ...o.differ] } as Out;
  for (const k of ["worlds", "stations", "logs", "bodiesOffered", "lacking", "on", "off", "waiting", "webs", "moved", "given", "toldOut", "stricter"] as const) out[k] = a[k] + o[k];
  return out;
});
const told = (what: string, o: Out) => {
  const refused = Object.values(o.refused).reduce((a, b) => a + b, 0);
  print(`${what}: ${o.worlds} worlds, ${o.stations} stations compared (moved ${o.moved}), ${o.logs} logs; bodies offered ${o.bodiesOffered}, refused ${refused} (${Object.entries(o.refused).map(([k, n]) => `${k}: ${n}`).join("; ") || "none"}); lacking ${o.lacking}; states on ${o.on}, off ${o.off}, waiting ${o.waiting} (of them "not on" at the model ${o.stricter}); web devices ${o.webs}; holders given to compared ${o.given}, told out ${o.toldOut}; ${o.differ.length} differ`);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
};

test("on the model's drawn worlds every station has the model keeper's logs, bodies, lacking, state and givings", async () => {
  const o = sum(await drawn);
  told("drawn", o);
  assert.equal(o.differ.length, 0, "the station and the model differ (the first are printed above)");
  assert.ok(Object.keys(o.refused).length > 0 && o.lacking > 0 && o.on > 0 && o.waiting > 0 && o.given > 0, "not trivial worlds");
});

test("on the model's scripted worlds too: bodies no one's, web devices by a keeper's clock, a revoked key, off and on again, the handover", async () => {
  const o = sum(await scripted);
  told("scripted", o);
  assert.equal(o.differ.length, 0, "the station and the model differ (the first are printed above)");
  assert.ok(o.off > 0 && o.webs > 0 && o.toldOut > 0 && o.moved > 0, "not trivial worlds");
});
