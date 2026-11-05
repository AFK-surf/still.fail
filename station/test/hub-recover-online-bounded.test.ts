import assert from "node:assert/strict";
import { test } from "node:test";
import { Hub } from "../src/sessions/hub.ts";

test("restart recovery finds a connect only for sessions with work to resume", () => {
  const reads: string[][] = [];
  for (const idle of [40, 400]) {
    const looked: string[] = [], resumed: string[] = [];
    const row = (key: string, running = false, connect = "connected") => ({ key, running, connect });
    const idleRows = Array.from({ length: idle }, (_, i) => row(`idle-${i}`));
    const waiting = row("waiting"), refill = row("refill"), offline = row("offline", false, "offline");
    const running = row("running", true), active = row("active"), empty = row("empty");
    const live = [...idleRows, waiting, refill, offline, running, active, empty];
    const turns = new Map<string, any>([
      ...idleRows.map((r) => [r.key, { endedAt: 1, outcome: "ok", declared: "done" }] as const),
      [waiting.key, { endedAt: 1, declared: "waiting" }],
      [refill.key, { endedAt: 1, outcome: "failed", detail: "rate_limit:later", declared: "waiting" }],
      [offline.key, { endedAt: 1, declared: "waiting" }],
      [running.key, { endedAt: 1, declared: "waiting" }],
      [active.key, { endedAt: null, declared: "waiting" }],
    ]);
    const hub = Object.assign(Object.create(Hub.prototype), {
      adopted: new Set([running.key]),
      store: {
        runningSessions: () => [running], sessionsWithPending: () => [], liveSessions: () => live,
        lastTurnsOf: () => turns, latestThread: (key: string) => { looked.push(key); return null; },
      },
      chatOf: (connect: string) => connect === "connected" ? {} : undefined,
      actor: (r: { key: string }) => ({
        takeWait: () => { resumed.push(`wait:${r.key}`); },
        takeRefill: () => { resumed.push(`refill:${r.key}`); },
      }),
    });
    hub.recover();
    assert.deepEqual(resumed, ["wait:waiting", "refill:refill"]);
    reads.push(looked);
  }
  assert.deepEqual(reads, [["waiting", "refill", "offline"], ["waiting", "refill", "offline"]]);
});
