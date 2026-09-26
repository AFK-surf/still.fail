import assert from "node:assert/strict";
import { test } from "node:test";
import type { Profile } from "../src/config.ts";
import { pickProfile, type ProfileHealth } from "../src/pool.ts";

const profile = (id: string, models: string[] = []): Profile => ({ id, name: id, runtime: "claude", home: `/h/${id}`, env: {}, models, access: { kind: "env", key: "" } } as unknown as Profile);
const ok = (models: string[] | null = null) => ({ state: "ok" as const, detail: "", models, checkedAt: 0 });
const quota = (used: number) => ({ state: "ok" as const, windows: [{ label: "5 小时", usedPercent: used, resetsAt: null }], detail: null, checkedAt: 0 });

test("the pool skips broken, spent and unfit profiles, then prefers headroom, then fewer sessions, then the least recently picked", () => {
  const a = profile("a", ["m1"]), b = profile("b", ["m1"]), c = profile("c", ["m1", "m2"]), d = profile("d", ["m2"]);
  const health: Record<string, ProfileHealth> = {
    a: { check: { ...ok(), state: "failed" }, quota: quota(0) },
    b: { check: ok(["m1"]), quota: quota(100) },
    c: { check: ok(["m1", "m2"]), quota: quota(60) },
    d: { check: ok(["m2"]), quota: quota(20) },
  };
  const signals = (load: Record<string, number> = {}, picked: Record<string, number> = {}) => ({
    health: (id: string) => health[id]!, load: (id: string) => load[id] ?? 0, lastPicked: (id: string) => picked[id] ?? 0,
  });
  assert.equal(pickProfile([a, b, c, d], "m1", signals()).id, "c", "a failed, b spent, d lacks m1");
  assert.equal(pickProfile([a, b, c, d], "m2", signals()).id, "d", "most headroom");
  assert.equal(pickProfile([a, b, c, d], null, signals()).id, "d");
  health.c = { check: ok(), quota: quota(20) };
  assert.equal(pickProfile([c, d], null, signals({ d: 2, c: 1 })).id, "c", "fewer sessions");
  assert.equal(pickProfile([c, d], null, signals({}, { c: 5, d: 1 })).id, "d", "least recently picked");
  assert.equal(pickProfile([a], "m1", signals()).id, "a", "nothing healthy: still one, so the failure shows");
  assert.throws(() => pickProfile([a, b], "m2", signals()), /no profile has m2 enabled/, "a model enabled nowhere is refused");
  assert.equal(pickProfile([a, c], "m9", signals(), false).id, "c", "a connect's binding still runs on its healthy profiles");
});
