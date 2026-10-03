// The pages' delta applier (web/src/core/delta.ts) takes the TS core's keyed ops (client/core-ts/src/collections.ts):
// what it makes is the core's value, and the rows that did not change are the same objects.
import assert from "node:assert/strict";
import { test } from "node:test";
import { applyDelta, type DeltaOp } from "../../../web/src/core/delta.ts";
import { diffKeyed, specOf } from "../src/collections.ts";

const row = (station: string, id: string, title = id) => ({ station, id, title, unread: false });

test("keyed ops from the core apply and keep unchanged rows", () => {
  let seed = 11;
  const rand = (n: number) => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed % n;
  };
  const spec = specOf({ topic: "chats", scope: "ws" });
  for (let round = 0; round < 200; round++) {
    const day = (daysAgo: number, n: number) => ({ daysAgo, label: `d${daysAgo}`, items: Array.from({ length: n }, (_, i) => row(`ws/${rand(3)}`, `t${daysAgo}-${i}`)) });
    const old = { loading: false, days: [day(0, rand(8)), day(1, rand(8)), day(3, rand(8))] };
    const next = structuredClone(old);
    for (const d of next.days) {
      d.items = d.items.filter(() => rand(5) > 0).map((r) => (rand(4) === 0 ? { ...r, unread: true } : r));
      if (rand(2) === 0 && d.items.length > 1) d.items.unshift(d.items.splice(rand(d.items.length), 1)[0]!);
      if (rand(3) === 0) d.items.splice(rand(d.items.length + 1), 0, row("ws/9", `n${round}`));
    }
    if (rand(4) === 0) next.days.splice(1, 1);
    const ops = diffKeyed(old, next, spec) as DeltaOp[];
    const applied = applyDelta(old, ops) as typeof old;
    assert.deepEqual(applied, next);
    // A row whose key and value are as before is the very object it was.
    const before = new Map(old.days.flatMap((d) => d.items.map((r) => [`${d.daysAgo}/${r.station}/${r.id}`, r] as const)));
    for (const d of applied.days) {
      for (const r of d.items) {
        const was = before.get(`${d.daysAgo}/${r.station}/${r.id}`);
        if (was && JSON.stringify(was) === JSON.stringify(r)) assert.equal(r, was);
      }
    }
  }
});
