// The core's reading of a workspace said in its people's own logs (src/lock-moved.ts, the person logs kept by
// src/lock-keep.ts) held to the fourth round's model (test/lock-moved-check.ts says what is compared and how; where the
// core is stricter on purpose, as the station is: "not on" and "no root" are `waiting`, naming nobody). Drawn worlds
// (both of round three's variants, fault-free and with faults; as drawn, one body held back for good, two workspaces)
// and the scripted ones (M2, M5 with its clocks, a revoked key's web device and `off`, M6, M7's four rows, M8's two: the chain carried once moved, so nothing waits for an `open`), every
// device keeper at each look. LOCK_MOVED_CORE_SEEDS (3), _STEPS (120), _SCRIPTED (1) give more.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pool, print } from "../../../station/test/lock-fork-pool.ts";
import { V3 } from "../../../station/test/lock-roster-model.ts";
import type { Job, Out } from "./lock-moved-check.ts";

const SEEDS = Number(process.env.LOCK_MOVED_CORE_SEEDS ?? 3);
const STEPS = Number(process.env.LOCK_MOVED_CORE_STEPS ?? 120);
const SCRIPTED = Number(process.env.LOCK_MOVED_CORE_SCRIPTED ?? 1);
const FAMILIES = ["free", "faults"] as const;

const ask = pool<Job>(new URL("./lock-moved-check.ts", import.meta.url), { movedCore: true });
const drawn = Promise.all(V3.flatMap((_, v) => FAMILIES.flatMap((family) => Array.from({ length: SEEDS }, (_, i) => ask<Out>({ t: "drawn", v, family, from: i + 1, to: i + 1, steps: STEPS })))));
const scripted = Promise.all(Array.from({ length: SCRIPTED }, (_, i) => ask<Out>({ t: "scripted", from: i + 1, to: i + 1 })));

const COUNTS = ["worlds", "keepers", "logs", "bodiesOffered", "lacking", "on", "off", "waiting", "webs", "moved", "stricter"] as const;
const sum = (os: Out[]): Out => os.reduce((a, o) => {
  const refused = { ...a.refused };
  for (const [k, n] of Object.entries(o.refused)) refused[k] = (refused[k] ?? 0) + n;
  const out = { ...a, refused, differ: [...a.differ, ...o.differ] } as Out;
  for (const k of COUNTS) out[k] = a[k] + o[k];
  return out;
});
const refusedAll = (o: Out) => Object.values(o.refused).reduce((a, b) => a + b, 0);
const told = (what: string, o: Out) => {
  print(`${what}: ${o.worlds} worlds, ${o.keepers} device keepers compared (moved ${o.moved}), ${o.logs} logs; bodies offered ${o.bodiesOffered}, refused ${refusedAll(o)} (${Object.entries(o.refused).map(([k, n]) => `${k}: ${n}`).join("; ") || "none"}); lacking ${o.lacking}; states on ${o.on}, off ${o.off}, waiting ${o.waiting} (of them "not on" at the model ${o.stricter}); web devices ${o.webs}; ${o.differ.length} differ`);
  for (const d of o.differ.slice(0, 3)) print(`  ${d.slice(0, 300)}`);
};

test("on the model's drawn worlds every device keeps the model keeper's logs, bodies, lacking and state", async () => {
  const o = sum(await drawn);
  told("drawn", o);
  assert.equal(o.differ.length, 0, "the core and the model differ (the first are printed above)");
  assert.ok(refusedAll(o) > 0 && o.lacking > 0 && o.on > 0 && o.moved > 0, "not trivial worlds");
});

test("on the model's scripted worlds too: bodies no one's, web devices by a device's clock, a revoked key, off and on again, the handover", async () => {
  const o = sum(await scripted);
  told("scripted", o);
  assert.equal(o.differ.length, 0, "the core and the model differ (the first are printed above)");
  assert.ok(o.off > 0 && o.webs > 0 && o.moved > 0 && Object.keys(o.refused).length >= 3, "not trivial worlds");
});
